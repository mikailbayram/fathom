# frozen_string_literal: true

module Corpus
  # The one retrieval path in the application.
  #
  #   Corpus::Search.new(scan).find("custom RBAC roles", scope: :buyer_visible)
  #
  # Findings analysis and the chatbot both come through here, which is what
  # makes a chatbot answer and a finding's evidence the same claim.
  class Search
    SCOPES = {
      all: nil,
      buyer_visible: CorpusTypes::BUYER_VISIBLE,
      deep: CorpusTypes::DEEP
    }.freeze

    class UnknownScope < ArgumentError; end

    def initialize(scan, embedder: nil)
      @scan = scan
      @embedder = embedder || AI::Embedder.build(scan: scan)
    end

    def find(query, scope: :all, limit: nil)
      query = query.to_s
      scope = scope.to_sym
      raise UnknownScope, "Unknown retrieval scope #{scope.inspect}" unless SCOPES.key?(scope)
      return [] if query.blank?

      chunks = scoped_chunks(SCOPES.fetch(scope))
      return [] unless chunks.exists?

      Ranking.new(
        semantic: semantic_candidates(chunks, query),
        lexical: lexical_candidates(chunks, query)
      ).top(limit || WebsiteIntelligence.config.final_retrieval_results)
    end

    private
      attr_reader :scan, :embedder

      def scoped_chunks(corpus) = scan.chunks.embedded.in_corpus(corpus)

      def semantic_candidates(chunks, query)
        vector = embedder.embed_one(query)
        return [] if vector.blank?

        chunks
          .nearest_neighbors(:embedding, vector, distance: "cosine")
          .limit(WebsiteIntelligence.config.semantic_results)
          .map { |chunk| Candidate.new(chunk: chunk, similarity: chunk.neighbor_distance && 1 - chunk.neighbor_distance) }
      end

      # The lexical half exists because vectors are weakest exactly where
      # enterprise buyers are most precise: SCIM, RPO, SOC 2, NetSuite.
      def lexical_candidates(chunks, query)
        tsquery = Arel.sql("websearch_to_tsquery('english', #{Chunk.connection.quote(query)})")

        chunks
          .where(Arel.sql("search_vector @@ #{tsquery}"))
          .select(Chunk.arel_table[Arel.star], Arel.sql("ts_rank(search_vector, #{tsquery}) AS lexical_rank_score"))
          .order(Arel.sql("ts_rank(search_vector, #{tsquery}) DESC, chunks.id ASC"))
          .limit(WebsiteIntelligence.config.lexical_results)
          .map { |chunk| Candidate.new(chunk: chunk, lexical_score: chunk.attributes["lexical_rank_score"].to_f) }
      end
  end
end
