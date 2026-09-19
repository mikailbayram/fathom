# frozen_string_literal: true

module Corpus
  # One chunk under consideration, carrying the evidence for why it surfaced.
  class Candidate
    attr_reader :chunk, :similarity, :lexical_score
    attr_accessor :semantic_rank, :lexical_rank, :score

    def initialize(chunk:, similarity: nil, lexical_score: nil, semantic_rank: nil, lexical_rank: nil, score: 0.0)
      @chunk = chunk
      @similarity = similarity
      @lexical_score = lexical_score
      @semantic_rank = semantic_rank
      @lexical_rank = lexical_rank
      @score = score
    end

    delegate :id, :content, :corpus_type, :page_id, :excerpt, to: :chunk

    def source_url = chunk.metadata["url"]
    def source_title = chunk.metadata["title"]
    def page_type = chunk.metadata["page_type"]
    def heading = chunk.metadata["heading"]

    def semantic? = semantic_rank.present?
    def lexical? = lexical_rank.present?
    def both? = semantic? && lexical?

    def source_attributes(primary: false)
      {
        chunk_id: chunk.id,
        relevance_score: score.to_f.round(4),
        is_primary: primary,
        corpus_type: chunk.corpus_type,
        quoted_excerpt: chunk.excerpt
      }
    end
  end
end
