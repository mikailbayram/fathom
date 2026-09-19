# frozen_string_literal: true

module AI
  class Embedder
    # Live embeddings through RubyLLM's configured provider.
    class Live < Embedder
      def embed(texts)
        texts = Array(texts)
        return [] if texts.empty?

        ExternalRequests.guard!("embeddings via #{model.id}")
        SpendingLimit.new(scan: scan).enforce!

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        embedding = RubyLLM.embed(texts, model: model.id, provider: model.provider, assume_model_exists: true)
        vectors = normalize_shape(embedding.vectors, texts)

        record(input_tokens: embedding.tokens&.input, cost: embedding.cost&.total, started: started)
        verify_dimensions!(vectors)
        vectors
      end

      private
        # A single text comes back as one flat vector; an array comes back as an
        # array of them.
        def normalize_shape(vectors, texts)
          texts.one? && !vectors.first.is_a?(Array) ? [ vectors ] : vectors
        end

        def verify_dimensions!(vectors)
          actual = vectors.first&.length
          return if actual.nil? || actual == dimensions

          raise WebsiteIntelligence::ConfigurationError, <<~MESSAGE.squish
            #{model.id} returned #{actual}-dimension vectors but chunks.embedding is
            vector(#{dimensions}). Set AI_EMBEDDING_DIMENSIONS and migrate before scanning.
          MESSAGE
        end
    end
  end
end
