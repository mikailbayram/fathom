# frozen_string_literal: true

module AI
  class Answerer
    # Grounded answering through the configured analysis model.
    class Live < Answerer
      def answer(question, scope: :all, candidates: nil, destination: nil)
        candidates ||= search.find(question, scope: scope)
        return unanswered(scope, search_effort: SearchEffort.derive(page: destination, domain: scan.domain)) if candidates.empty?

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

            #{effort_question(destination)}
          TEXT
        )

        coverage = response["coverage"].to_f.clamp(0.0, 1.0)
        effort = effort_for(response["search_effort"], destination, coverage)

        unless response["answerable"]
          return unanswered(scope, candidates, coverage: coverage, reasoning: response["reasoning_summary"].to_s,
                            search_effort: effort, search_path: response["search_path"].presence)
        end

        # A model may only cite ids it was actually shown; anything else is
        # discarded rather than trusted.
        cited = Array(response["supporting_chunk_ids"]).map(&:to_i) & candidates.map(&:id)
        if cited.empty?
          return unanswered(scope, candidates, reasoning: "The model cited no source it was shown.",
                            search_effort: effort, search_path: response["search_path"].presence)
        end

        Answer.new(
          answerable: true,
          text: response["answer"],
          coverage: coverage,
          chunk_ids: cited,
          reasoning: response["reasoning_summary"],
          candidates: candidates,
          scope: scope,
          search_effort: effort,
          search_path: response["search_path"].presence
        )
      end

      private
        # The second half of the buyer-visible check, and the reason it is asked
        # here rather than in a call of its own: the model has already read what
        # the marketing pages say, and the destination is known from the crawl.
        # Asking for a band rather than a duration is deliberate -- see SCHEMA.
        def effort_question(destination)
          <<~TEXT
            #{destination_block(destination)}

            Then judge search_effort: a buyer starts on the homepage, wants this answer,
            and does not know the page above exists. How far do they get?
            #{SearchEffort::ALL.map { |band| "  #{band} -- #{SearchEffort.meaning(band)}" }.join("\n")}
            Judge the site as it is, not as it should be. A fact stated only in
            documentation on a separate subdomain is not signposted because the
            documentation is good. Report search_path as one sentence naming what that
            buyer would actually have to do -- the clicks, the search, or giving up.
          TEXT
        end

        def destination_block(destination)
          return "This claim is published nowhere a buyer could reach." if destination.nil?

          "The claim is published on: #{destination.title} -- #{destination.url} " \
            "(#{PageTypes.label(destination.page_type)}, about #{destination.word_count} words)"
        end
    end
  end
end
