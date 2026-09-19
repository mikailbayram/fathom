# frozen_string_literal: true

module Corpus
  # A deterministic token estimate. It never calls a tokenizer service and the
  # same text always counts the same, which is what chunk sizing needs.
  #
  # Roughly four characters per token matches English closely enough to size
  # chunks by. It is never reported as a provider token count.
  class TokenCount
    CHARACTERS_PER_TOKEN = 4.0

    def self.of(text) = new(text).to_i

    def initialize(text)
      @text = text.to_s
    end

    def to_i = @text.blank? ? 0 : (@text.length / CHARACTERS_PER_TOKEN).ceil

    def to_s = to_i.to_s
  end
end
