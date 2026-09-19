# frozen_string_literal: true

module AI
  class Embedder
    # Deterministic embeddings with no provider behind them.
    #
    # These are not noise: each token is hashed into a fixed bucket with a
    # stable sign, so two texts sharing vocabulary genuinely land near each
    # other. That keeps pgvector similarity a real part of the pipeline in fake
    # mode instead of a stub -- the retrieval, ranking and source selection
    # under test are the ones that run in production.
    class Fake < Embedder
      MODEL_NAME = "fake-hashing-v1"

      STOPWORDS = %w[
        a an the and or but if of to in on for with without from by at as is are
        was were be been being do does did can could should would will shall may
        it its this that these those you your we our they their he she them us
      ].to_set.freeze

      def embed(texts)
        texts = Array(texts)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        vectors = texts.map { |text| vector_for(text) }

        # Fake work is still recorded, so cost reporting and the spending limit
        # run the same code path in every mode.
        record(input_tokens: texts.sum { |text| Corpus::TokenCount.of(text) }, cost: 0, started: started)
        vectors
      end

      def model = Models::Model.new(role: :embedding, id: MODEL_NAME, provider: :fake)

      private
        def vector_for(text)
          vector = Array.new(dimensions, 0.0)

          tokens(text).tally.each do |token, count|
            digest = Digest::SHA256.digest(token)
            index = digest.unpack1("N") % dimensions
            sign = digest.getbyte(4).even? ? 1.0 : -1.0
            vector[index] += sign * (1.0 + Math.log(count))
          end

          normalize(vector, text)
        end

        def tokens(text)
          words = text.to_s.downcase.scan(/[a-z0-9][a-z0-9_.-]*/).reject { |word| STOPWORDS.include?(word) }
          # Adjacent pairs give the vector some word-order sensitivity, which
          # matters for phrases like "custom roles" and "data residency".
          words + words.each_cons(2).map { |pair| pair.join(" ") }
        end

        def normalize(vector, text)
          magnitude = Math.sqrt(vector.sum { |value| value * value })

          if magnitude.zero?
            # Empty or stopword-only text still needs a stable unit vector
            # rather than an all-zero one pgvector cannot rank.
            vector[Digest::SHA256.digest(text.to_s).unpack1("N") % dimensions] = 1.0
            return vector
          end

          vector.map { |value| value / magnitude }
        end
    end
  end
end
