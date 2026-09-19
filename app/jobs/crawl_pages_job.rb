# frozen_string_literal: true

# Stage three: fetch the selected pages, a batch at a time.
#
# The job re-enqueues itself while work remains rather than fetching thousands
# of pages in one execution, so a crash costs one batch and progress is visible
# while it runs.
class CrawlPagesJob < PipelineJob
  BATCH_SIZE = 10

  # Firecrawl meters requests per minute against the account, not per scan. Too
  # many crawls at once and nearly every request is refused and retried, so the
  # queue moves at the speed of the backoff rather than the API -- and a 429
  # still costs a credit.
  #
  # Solid Queue holds the rest in solid_queue_blocked_executions and releases
  # them as slots free, which is a queue with automatic release and an expiry
  # safety valve. Writing that again in application code would be strictly
  # worse than using it.
  limits_concurrency to: WebsiteIntelligence.config.max_concurrent_scans,
                     key: Crawler::Client::CONCURRENCY_KEY, duration: 30.minutes

  # Spacing requests keeps us under the window instead of exhausting it and
  # then sleeping off a 20-second penalty.
  PACE = 1.2

  def stage = "crawling"

  private
    # The error most of the failures share, which is the one worth reporting.
    def dominant_error(scan)
      scan.discovered_urls.selected.where.not(crawl_error: nil).pluck(:crawl_error)
          .map { |message| message.to_s.split("(HTTP").first.to_s.strip.presence || message }
          .tally.max_by(&:last)&.first
    end

  public

  def perform(scan)
    ensure_mode!(scan)
    crawl = Website::Crawl.new(scan)
    batch = crawl.pending.limit(BATCH_SIZE).to_a

    batch.each_with_index do |discovered_url, index|
      sleep(PACE) if index.positive?
      crawl.fetch(discovered_url)
    end

    if crawl.complete?
      # Everything selected was attempted and none of it came back. Continuing
      # would produce a company profile from nothing, findings asserting that
      # nothing is published, and a demo that cannot answer its own suggested
      # questions -- all of it invented by the absence of data rather than
      # supported by it.
      if scan.pages.none?
        reason = dominant_error(scan) || "no page could be fetched"
        return scan.fail!(stage: stage, error: "Crawled 0 of #{scan.pages_selected} selected pages: #{reason}")
      end

      advance(scan)
    else
      self.class.perform_later(scan)
    end
  end
end
