# frozen_string_literal: true

module Crawler
  # The crawler every other object talks to. Nothing outside this namespace
  # knows whether pages arrive from Firecrawl or from a fixture on disk.
  class Client
    # One budget, shared by every job that touches the crawler API, because the
    # API meters the account rather than the scan.
    CONCURRENCY_KEY = "crawler"

    class Error < StandardError; end
    class NotFound < Error; end

    def self.build
      case WebsiteIntelligence.mode
      when :live then Firecrawl.new
      when :local then Local.new
      else Fake.new
      end
    end

    # Discovers public URLs for a site without fetching their content.
    def map(site_url) = raise NotImplementedError

    # Fetches one public document.
    def fetch(url) = raise NotImplementedError

    def configured? = true

    def name = self.class.name.demodulize
  end
end
