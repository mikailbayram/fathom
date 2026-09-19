# frozen_string_literal: true

module AI
  # Every object asks for a model *role*, never a literal model ID. Swapping
  # gpt-5.6-terra for something else -- or benchmarking one against another --
  # is then an environment change rather than a code change.
  module Models
    Model = Data.define(:role, :id, :provider) do
      def to_s = id
    end

    class << self
      def embedding = model(:embedding, config.embedding_model, config.embedding_provider)

      # Cheap, high-volume mechanical work: ambiguous page classification,
      # lightweight extraction, relevance judgments.
      def fast = model(:fast, config.fast_model)

      # Company understanding, question generation, grounded answering,
      # answer verification, finding analysis.
      def analysis = model(:analysis, config.analysis_model)

      def chat = model(:chat, config.chat_model)

      def all = { embedding: embedding, fast: fast, analysis: analysis, chat: chat }

      private
        def config = WebsiteIntelligence.config.ai

        def model(role, id, provider = config.provider) = Model.new(role: role, id: id, provider: provider)
    end
  end
end
