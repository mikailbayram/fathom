# frozen_string_literal: true

module AI
  # Turns text into vectors. Nothing that uses it cares which implementation is
  # behind it.
  #
  #   AI::Embedder.build(scan: scan).embed(["first chunk", "second chunk"])
  #
  class Embedder
    def self.build(scan: nil)
      WebsiteIntelligence.live_ai_enabled? ? Live.new(scan: scan) : Fake.new(scan: scan)
    end

    def initialize(scan: nil)
      @scan = scan
    end

    def embed(_texts) = raise NotImplementedError

    def embed_one(text) = embed([ text ]).first

    def dimensions = WebsiteIntelligence.config.ai.embedding_dimensions

    def model = Models.embedding

    private
      attr_reader :scan

      def record(operation: "embedding", input_tokens: nil, cost: nil, started:)
        AIUsage.record(
          operation: operation,
          provider: model.provider,
          model: model.id,
          scan: scan,
          input_tokens: input_tokens,
          estimated_cost: cost,
          duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000).round
        )
      end
  end
end
