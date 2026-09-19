# frozen_string_literal: true

module Corpus
  # Merges the semantic and lexical candidate lists into one ordering.
  #
  # Reciprocal rank fusion rather than a weighted sum of raw scores, because
  # cosine similarity and ts_rank are not on comparable scales, and because a
  # chunk found by both methods should outrank one found by either. Ranking
  # lives behind this object so it can be replaced -- with a cross-encoder
  # reranker, say -- without touching anything that consumes it.
  class Ranking
    K = 60.0

    def initialize(semantic:, lexical:)
      @semantic = semantic
      @lexical = lexical
    end

    def top(limit)
      merged.values.sort_by { |candidate| [ -candidate.score, candidate.chunk.id ] }.first(limit)
    end

    private
      def merged
        @merged ||= begin
          merged = {}

          @semantic.each_with_index do |candidate, index|
            candidate.semantic_rank = index + 1
            merged[candidate.chunk.id] = candidate
          end

          @lexical.each_with_index do |candidate, index|
            if (existing = merged[candidate.chunk.id])
              existing.lexical_rank = index + 1
            else
              candidate.lexical_rank = index + 1
              merged[candidate.chunk.id] = candidate
            end
          end

          merged.each_value { |candidate| candidate.score = fuse(candidate) }
          merged
        end
      end

      def fuse(candidate)
        semantic = candidate.semantic_rank ? 1.0 / (K + candidate.semantic_rank) : 0.0
        lexical = candidate.lexical_rank ? 1.0 / (K + candidate.lexical_rank) : 0.0
        ((semantic + lexical) * 100).round(6)
      end
  end
end
