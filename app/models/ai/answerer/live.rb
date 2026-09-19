# frozen_string_literal: true

module AI
  class Answerer
    # Grounded answering through the configured analysis model.
    class Live < Answerer
      def answer(question, scope: :all, candidates: nil)
        candidates ||= search.find(question, scope: scope)
        return unanswered(scope) if candidates.empty?

        response = Client.new(model: model, operation: operation_for(scope), scan: scan).structured(
          schema: SCHEMA,
          instructions: Prompts::GROUNDING_RULES,
          prompt: <<~TEXT
            Claim: #{question}

            #{Prompts.untrusted_material(candidates)}

            Answer the claim using only the sources above.

            Then rate coverage: how completely these sources establish the claim.
            Nothing about it in the sources is 0. A passing mention that leaves the
            specifics open is around 0.3. The claim stated outright, with its
            numbers or terms, is 1. Rate the sources, not how sure you are of your
            own answer -- a confident "the sources do not say" is coverage 0.
          TEXT
        )

        unless response["answerable"]
          return unanswered(scope, candidates, coverage: response["coverage"].to_f.clamp(0.0, 1.0),
                            reasoning: response["reasoning_summary"].to_s)
        end

        # A model may only cite ids it was actually shown; anything else is
        # discarded rather than trusted.
        cited = Array(response["supporting_chunk_ids"]).map(&:to_i) & candidates.map(&:id)
        return unanswered(scope, candidates, reasoning: "The model cited no source it was shown.") if cited.empty?

        Answer.new(
          answerable: true,
          text: response["answer"],
          coverage: response["coverage"].to_f.clamp(0.0, 1.0),
          chunk_ids: cited,
          reasoning: response["reasoning_summary"],
          candidates: candidates,
          scope: scope
        )
      end
    end
  end
end
