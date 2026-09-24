# frozen_string_literal: true

module AI
  class Responder
    # Answers from the retrieved corpus with the same deterministic evidence
    # scoring the fake answerer uses, so retrieval, grounding, sources and
    # refusal are all exercised without a provider.
    #
    # It composes a reply rather than pasting the passage back, because a demo
    # that recites documentation reads like a search box, not an assistant. The
    # composition is deterministic and adds no facts: the sentences are the
    # company's, the framing around them is ours.
    class Fake < Responder
      def answer(question, &on_text)
        query = search_query(question)
        # Anchored before answering, not after: filtering the sources of an
        # answer that was already composed from elsewhere leaves the prose
        # wandering and the citations empty.
        candidates = anchored(search.find(query), question)
        result = Answerer::Fake.new(chatbot.scan, search: search).answer(query, candidates: candidates)
        return unavailable(question, candidates) unless result.answerable?

        Reply.new(
          content: deliver(compose(question, result), &on_text),
          sources: sources_from(candidates, result.chunk_ids),
          grounded: true,
          kind: "answer",
          chunk_ids: result.chunk_ids
        )
      end

      # Three sentences is a reply; six is a documentation page pasted into a
      # chat window.
      MAX_SENTENCES = 3

      private
        # There is no provider here and so nothing genuinely arrives over time
        # -- the whole answer exists at once. Handing it over a sentence at a
        # time anyway is what keeps the path that carries a live reply to the
        # visitor exercised when the app runs without a provider, which is how
        # it runs in development and in the whole test suite. No delay is
        # invented: sentences that land in the same instant go out as one.
        def deliver(content)
          return content unless block_given?

          so_far = +""
          content.split(/(?<=[.!?])\s+/).each do |sentence|
            so_far << " " unless so_far.empty?
            so_far << sentence
            yield so_far.dup
          end

          content
        end

        # No opener. "Acme's documentation covers this" tells the reader nothing
        # they did not already know from having asked.
        def compose(_question, answer)
          body = answer.text.to_s.squish.split(/(?<=[.!?])\s+/).first(MAX_SENTENCES).join(" ")

          [ body, qualifier_in(body) ].compact.join(" ")
        end

        # Plan gating and hard limits are the details a buyer needs pointed out,
        # and they are already in the quoted text -- this only draws attention.
        def qualifier_in(body)
          return "Note that this is tied to a specific plan." if body.match?(/\b(?:Enterprise|Business|Starter|Growth)\s+plan\b/)
          return "Note the stated limit." if body.match?(/\b\d+\s*(?:times|retries|days|hours|minutes|requests)\b/i)

          nil
        end
    end
  end
end
