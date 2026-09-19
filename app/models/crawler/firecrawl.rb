# frozen_string_literal: true

module Crawler
  # Live crawling through Firecrawl's v2 API.
  #
  # Every request passes ExternalRequests.guard!, so this object cannot spend
  # money unless the operator has set APP_MODE=live and ENABLE_LIVE_AI=true.
  class Firecrawl < Client
    # Trailing slash, and relative request paths below: Faraday *replaces*
    # the base path when a request path starts with "/", which silently
    # drops the /v2 and 404s.
    BASE_URL = "https://api.firecrawl.dev/v2/"

    # Firecrawl's plans are metered per minute, and a scan is a burst of
    # requests by nature. Without this every page after the first minute's
    # allowance simply fails, which is how a scan reaches "completed" having
    # read nothing at all.
    # Raised internally to drive the retry; never leaves this class.
    class RateLimited < StandardError; end

    RATE_LIMIT_ATTEMPTS = 4
    RATE_LIMIT_BACKOFF = [ 3, 8, 20 ].freeze

    def initialize(api_key: ENV["FIRECRAWL_API_KEY"], timeout: 60)
      @api_key = api_key
      @timeout = timeout
    end

    def configured? = @api_key.present?

    def map(site_url)
      body = post("map", {
        url: site_url,
        sitemap: "include",
        includeSubdomains: true,
        ignoreQueryParameters: false,
        limit: WebsiteIntelligence.config.max_discovered_urls
      })

      Array(body["links"]).filter_map do |link|
        url = link.is_a?(Hash) ? link["url"] : link
        next if url.blank?

        MappedUrl.new(url: url, source: "crawler_map",
                      metadata: { "title" => (link["title"] if link.is_a?(Hash)) }.compact)
      end
    end

    def fetch(url)
      data = post("scrape", { url: url, formats: [ "markdown" ], onlyMainContent: true, timeout: @timeout * 1_000 })["data"] || {}
      metadata = data["metadata"] || {}

      Document.new(
        url: metadata["url"].presence || metadata["sourceURL"].presence || url,
        title: Array(metadata["title"]).first,
        content: data["markdown"].to_s,
        http_status: metadata["statusCode"] || 200,
        links: Array(data["links"]),
        metadata: {
          "content_type" => metadata["contentType"],
          "description" => Array(metadata["description"]).first
        }.compact
      )
    end

    # The smallest safe request that proves the credential works. Used by
    # app:doctor and before any expensive live scan.
    def validate_credential!
      raise Error, "FIRECRAWL_API_KEY is not configured" unless configured?

      post("map", { url: "https://example.com", limit: 1 })
      true
    end

    private
      def connection
        @connection ||= Faraday.new(url: self.class::BASE_URL) do |faraday|
          faraday.request :json
          faraday.response :json
          faraday.options.timeout = @timeout
          faraday.options.open_timeout = 15
        end
      end

      def post(path, payload)
        ExternalRequests.guard!("Firecrawl #{path}")
        raise Error, "FIRECRAWL_API_KEY is not configured" unless configured?

        attempt = 0
        begin
          attempt += 1
          response = connection.post(path, payload) do |request|
            request.headers["Authorization"] = "Bearer #{@api_key}"
          end

          if response.status == 429 && attempt < RATE_LIMIT_ATTEMPTS
            sleep(retry_after(response) || RATE_LIMIT_BACKOFF[attempt - 1] || RATE_LIMIT_BACKOFF.last)
            raise RateLimited
          end

          unless response.success?
            detail = response.body["error"] if response.body.is_a?(Hash)
            raise Error, "Firecrawl #{path} failed (HTTP #{response.status})#{": #{detail}" if detail}"
          end

          response.body.is_a?(Hash) ? response.body : {}
        rescue RateLimited
          retry
        end
      rescue Faraday::Error => error
        raise Error, "Firecrawl #{path} failed: #{error.message}"
      end

      # Honoured when the API sends it, because it knows the window better than
      # a fixed backoff does.
      def retry_after(response)
        seconds = response.headers["retry-after"].to_i
        seconds.positive? ? [ seconds, 60 ].min : nil
      end
  end
end
