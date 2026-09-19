# frozen_string_literal: true

module Crawler
  # One URL learned during the mapping stage, before anything is fetched.
  MappedUrl = Data.define(:url, :source, :metadata) do
    def initialize(url:, source:, metadata: {}) = super
  end
end
