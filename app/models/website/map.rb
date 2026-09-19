# frozen_string_literal: true

module Website
  # Stage one: build an inventory of a company's public URLs before fetching
  # anything.
  #
  #   Website::Map.new(scan).discover!
  #
  # Mapping is deliberately separate from crawling. Knowing that a site has
  # eighteen thousand URLs is what lets the next stage choose two thousand of
  # them on purpose instead of fetching everything and hoping.
  class Map
    def initialize(scan, crawler: nil)
      @scan = scan
      @crawler = crawler || Crawler::Client.build
    end

    def discover!
      records = []

      DiscoveredUrl.transaction do
        # Remapping invalidates everything downstream, so the scan is cleared
        # back to empty rather than left holding findings that cite pages whose
        # URLs are gone.
        scan.claims.destroy_all
        scan.findings.destroy_all
        scan.chunks.delete_all
        scan.pages.delete_all
        scan.discovered_urls.delete_all

        mapped.each do |url, entry|
          records << attributes_for(url, entry)
        end

        DiscoveredUrl.insert_all!(records, record_timestamps: true) if records.any?
      end

      # insert_all! writes past the association, which would otherwise keep
      # serving the empty collection it cached during delete_all.
      scan.discovered_urls.reset
      # Remapping invalidates the previous classification pass too.
      scan.update!(urls_discovered: records.size, urls_classified_at: nil, claims_extracted_at: nil, coverage_audited_at: nil)
      self
    end

    def summary
      urls = scan.discovered_urls
      {
        total: urls.count,
        by_source: urls.group(:source).count,
        by_host: urls.group(:host).count.sort_by { |_, count| -count }.to_h,
        by_corpus: urls.group(:corpus_type).count
      }
    end

    private
      attr_reader :scan, :crawler

      # Deduplicated on the canonical URL, so the same page reached from the
      # sitemap, an internal link and the crawler's own map is one entry. The
      # first source that found it wins, which keeps provenance meaningful.
      def mapped
        @mapped ||= begin
          seen = {}
          limit = WebsiteIntelligence.config.max_discovered_urls

          crawler.map(scan.website_url).each do |entry|
            break if seen.size >= limit

            url = Url.new(entry.url, domain: scan.domain)
            next unless url.valid?
            next unless url.within_site?
            next if seen.key?(url.canonical)

            seen[url.canonical] = [ url, entry ]
          end

          seen.values
        end
      end

      def attributes_for(url, entry)
        classification = url.classification

        {
          scan_id: scan.id,
          url: url.to_s,
          canonical_url: url.canonical,
          host: url.host,
          path: url.path,
          source: entry.source,
          page_type: classification.page_type,
          corpus_type: classification.corpus_type,
          priority: classification.priority,
          selected_for_crawl: false,
          metadata: entry.metadata.merge(
            "reason" => classification.reason,
            "confident" => classification.confident?,
            "redundant_variant" => url.redundant_variant?,
            "subdomain" => url.subdomain
          ).compact
        }
      end
  end
end
