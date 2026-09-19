# frozen_string_literal: true

module Crawler
  # Optional local-mode crawler: a self-hosted Firecrawl over the same API, so
  # nothing but the base URL changes. Local mode is never required for
  # development or tests.
  class Local < Firecrawl
    def initialize(base_url: ENV.fetch("LOCAL_CRAWLER_URL", "http://localhost:3002/v2/"), **options)
      super(api_key: ENV.fetch("LOCAL_CRAWLER_API_KEY", "local"), **options)
      # Same trailing-slash requirement as the hosted client.
      @base_url = base_url.end_with?("/") ? base_url : "#{base_url}/"
    end

    def configured? = @base_url.present?

    private
      def connection
        @connection ||= Faraday.new(url: @base_url) do |faraday|
          faraday.request :json
          faraday.response :json
          faraday.options.timeout = @timeout
        end
      end
  end
end
