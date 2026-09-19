# frozen_string_literal: true

module AI
  # Answers one buyer question against one corpus, strictly from retrieved
  # source material.
  #
  #   answerer = AI::Answerer.build(scan)
  #   answerer.answer(claim.question_text, scope: :buyer_visible)
  #
  # Since the claims pivot this is asked of the buyer-visible corpus: the deep
  # side already has its answer and its source, and what remains open is whether
  # a buyer could have found it.
  class Answerer
    # coverage: how completely the retrieved sources establish the claim, from
    # 0 (they say nothing about it) to 1 (they state it outright). It is a
    # property of the corpus, and it is what the product measures.
    Answer = Data.define(:answerable, :text, :coverage, :chunk_ids, :reasoning, :candidates, :scope,
                         :search_effort, :search_path) do
      def answerable? = answerable

      def primary_candidate = candidates.detect { |candidate| chunk_ids.first == candidate.id } || candidates.first

      def source_attributes
        candidates.select { |candidate| chunk_ids.include?(candidate.id) }
                  .map.with_index { |candidate, index| candidate.source_attributes(primary: index.zero?) }
      end
    end

    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[answerable answer coverage supporting_chunk_ids reasoning_summary search_effort search_path],
      properties: {
        answerable: { type: "boolean" },
        answer: { type: "string" },
        # Asked for by name and defined in the prompt, because a field called
        # "confidence" gets answered with the model's certainty in its own
        # verdict -- "I am 99% sure this is not stated" -- which is the exact
        # opposite of what it was read as. Every buried fact scored as
        # prominently available, and no scan produced a single finding.
        coverage: {
          type: "number", minimum: 0, maximum: 1,
          description: "How completely the sources establish the claim: 0 if they are silent on it, " \
                       "1 if they state it outright. Not your confidence in your own answer."
        },
        supporting_chunk_ids: { type: "array", items: { type: "integer" } },
        reasoning_summary: { type: "string" },
        # Asked as a band, never as a duration. A model given "how many minutes"
        # answers with a plausible-looking number it has no way to know, and the
        # number then gets read as a measurement. Four bands it can actually
        # reason about, mapped to a range by SearchEffort.
        search_effort: {
          type: "string", enum: SearchEffort::ALL,
          description: "How hard a buyer starting from the homepage, who does not know the " \
                       "destination page exists, would have to work to reach this claim."
        },
        search_path: {
          type: "string",
          description: "One sentence naming what that buyer would actually have to do."
        }
      }
    }.freeze

    def self.build(scan)
      klass = WebsiteIntelligence.live_ai_enabled? ? Live : Fake
      klass.new(scan)
    end

    def initialize(scan, model: Models.analysis, search: nil)
      @scan = scan
      @model = model
      @search = search || Corpus::Search.new(scan)
    end

    # destination: the page the claim was published on, which is known before
    # this runs. The buyer-visible corpus decides whether the journey leads
    # there; the destination decides how far there is.
    def answer(question, scope: :all, candidates: nil, destination: nil) = raise NotImplementedError

    private
      attr_reader :scan, :model, :search

      def operation_for(scope) = scope == :buyer_visible ? "answer_buyer_visible" : "answer_full"

      # coverage is reported even when the answer is rejected: "the buyer-visible
      # site half-says this" and "the buyer-visible site is silent" are different
      # findings, and collapsing both to zero loses the distinction the whole
      # product rests on.
      def unanswered(scope, candidates = [], coverage: 0.0,
                     reasoning: "No public source material addressed the question.",
                     search_effort: nil, search_path: nil)
        Answer.new(answerable: false, text: nil, coverage: coverage.round(2), chunk_ids: [],
                   reasoning: reasoning, candidates: candidates, scope: scope,
                   search_effort: search_effort, search_path: search_path)
      end

      # A band the model did not supply, or supplied outside the vocabulary, is
      # not a band. The rule decides instead of a typo deciding.
      def effort_for(value, destination, coverage)
        return value.to_s if SearchEffort.valid?(value)

        SearchEffort.derive(page: destination, coverage: coverage, domain: scan.domain)
      end
  end
end
