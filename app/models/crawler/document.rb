# frozen_string_literal: true

module Crawler
  # One fetched public document, already reduced to text.
  Document = Data.define(:url, :title, :content, :http_status, :links, :metadata) do
    def initialize(url:, title: nil, content: "", http_status: 200, links: [], metadata: {}) = super

    def ok? = http_status.between?(200, 299)
  end
end
