# frozen_string_literal: true

module Website
  # Stage three: fetch the pages the plan selected, and only those.
  #
  #   Website::Crawl.new(scan).fetch(discovered_url)
  #
  # Each URL is fetched at most once. A URL that fails is marked as attempted
  # with its error, so one dead page never stalls or repeats a whole scan.
  class Crawl
    def initialize(scan, crawler: nil)
      @scan = scan
      @crawler = crawler || Crawler::Client.build
    end

    def pending = scan.discovered_urls.selected.where(crawled_at: nil).by_priority

    def complete? = !pending.exists?

    def fetch(discovered_url)
      document = crawler.fetch(discovered_url.url)
      page = persist(discovered_url, document)
      discovered_url.update!(crawled_at: Time.current, crawl_error: nil)
      refresh_counters
      page
    rescue Crawler::Client::Error => error
      discovered_url.update!(crawled_at: Time.current, crawl_error: error.message.truncate(240))
      refresh_counters
      nil
    end

    private
      attr_reader :scan, :crawler

      def persist(discovered_url, document)
        cleaner = Corpus::Cleaner.new(document.content)
        canonical = Url.new(document.url, domain: scan.domain).canonical

        # Two URLs serving the same words are one page. Checked before the
        # insert as well as caught after it, because another worker in the same
        # batch can win the race.
        duplicate = scan.pages.where(content_hash: cleaner.digest).where.not(canonical_url: canonical).exists?
        return nil if duplicate

        page = scan.pages.find_or_initialize_by(canonical_url: canonical)
        page.assign_attributes(
          discovered_url: discovered_url,
          url: document.url,
          title: document.title.presence || discovered_url.path,
          page_type: discovered_url.page_type,
          corpus_type: discovered_url.corpus_type,
          content: cleaner.text,
          content_hash: cleaner.digest,
          http_status: document.http_status,
          word_count: cleaner.word_count,
          metadata: document.metadata.merge("source" => discovered_url.source)
        )
        page.save!
        page
      rescue ActiveRecord::RecordNotUnique
        # Another URL already produced byte-identical content. One page, not two.
        nil
      end

      # Broadcast as well as written: this is the number the page shows moving
      # while a crawl runs, and once per page is a rate a socket does not
      # notice.
      def refresh_counters
        scan.update_columns(
          pages_crawled: scan.pages.count,
          updated_at: Time.current
        )
        scan.broadcast_status!
      end
  end
end
