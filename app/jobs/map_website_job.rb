# frozen_string_literal: true

# Stage one: inventory the public URLs before fetching anything.
class MapWebsiteJob < PipelineJob
  # Mapping calls the same metered API, so it shares the crawler's budget.
  limits_concurrency to: WebsiteIntelligence.config.max_concurrent_scans,
                     key: Crawler::Client::CONCURRENCY_KEY, duration: 15.minutes

  def stage = "mapping"

  def perform(scan)
    ensure_mode!(scan)
    Website::Map.new(scan).discover!
    advance(scan)
  end
end
