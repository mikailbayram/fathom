# frozen_string_literal: true

module AI
  # Every object asks for a model *role*, never a literal model ID. Swapping
  # gpt-5.6-terra for something else -- or benchmarking one against another --
  # is then an environment change rather than a code change.
  module Models
    # effort is the provider's reasoning effort where the role sets one, and nil
    # everywhere it does not, which is every role but chat.
    Model = Data.define(:role, :id, :provider, :effort) do
      def initialize(role:, id:, provider:, effort: nil) = super

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

      def chat = model(:chat, config.chat_model, effort: config.chat_effort)

      def all = { embedding: embedding, fast: fast, analysis: analysis, chat: chat }

      private
        def config = WebsiteIntelligence.config.ai

        def model(role, id, provider = config.provider, effort: nil)
          Model.new(role: role, id: id, provider: provider, effort: effort)
        end
    end
  end
end
