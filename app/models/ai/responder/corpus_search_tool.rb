# frozen_string_literal: true

module AI
  class Responder
    # The corpus search, handed to the model as something it may call.
    #
    # The point is that it is a tool and not a preamble. A sales engineer does
    # not look something up before every sentence; they look something up when
    # they need a fact they do not have. Making retrieval a tool lets the model
    # hold a conversation, ask a clarifying question, or handle a greeting
    # without a pointless search, and reach for the corpus when the answer
    # actually depends on it -- possibly more than once, with better queries the
    # second time.
    #
    # Every passage it returns is recorded, so what the model was shown is known
    # rather than inferred, and a citation can be checked against it.
    class CorpusSearchTool < RubyLLM::Tool
      description <<~TEXT
        Search this company's own public website and documentation. Use it whenever the
        answer depends on a fact about the product: capabilities, limits, plans, pricing,
        security, integrations, reliability. Search again with different wording if the
        first results do not cover the question. Every factual claim you make must come
        from a passage this returns.
      TEXT

      parameter :query, description: "What to look for, in the words the documentation would use"

      attr_reader :surfaced

      def initialize(scan)
        super()
        @scan = scan
        @surfaced = []
      end

      def execute(query:)
        candidates = Corpus::Search.new(@scan).find(query)
        @surfaced.concat(candidates)

        return { results: [], note: "Nothing in the indexed corpus matched that." } if candidates.empty?

        {
          results: candidates.first(8).map do |candidate|
            {
              source_id: candidate.id,
              page: candidate.source_title,
              section: candidate.heading,
              page_type: candidate.page_type,
              url: candidate.source_url,
              passage: candidate.chunk.body.squish.truncate(700)
            }
          end
        }
      end

      def candidate_for(id) = @surfaced.find { |candidate| candidate.id == id }
    end
  end
end
