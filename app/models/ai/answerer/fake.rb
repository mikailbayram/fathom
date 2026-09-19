# frozen_string_literal: true

module AI
  class Answerer
    # Answers deterministically from the chunks retrieval actually returned.
    #
    # Nothing here is hard-coded per question: the coverage comes from how
    # much of the question the retrieved passages genuinely cover, and the
    # answer is quoted from those passages. Ask it something the corpus does not
    # address and it says so, which is the behaviour the product depends on.
    class Fake < Answerer
      # Below this, the evidence is too thin to call the question answered.
      ANSWERABLE_COVERAGE = 0.45
      # Measured coverage rarely reaches 1.0 even for a perfect passage, so it
      # is scaled before being reported.
      COVERAGE_SCALE = 1.25
      BOTH_METHODS_BONUS = 0.05
      MAX_SUPPORTING_CHUNKS = 3
      # A passage covering far less of the question than the best one is not
      # evidence for it.
      SUPPORTING_COVERAGE_RATIO = 0.6
      # Quoting is stricter than counting. An answer can legitimately be
      # assembled from several passages, but a weak one from an unrelated page
      # should not put words into it.
      QUOTABLE_COVERAGE_RATIO = 0.9

      def answer(question, scope: :all, candidates: nil)
        candidates ||= search.find(question, scope: scope)
        return unanswered(scope) if candidates.empty?

        terms = Terms.new(question)
        ranked = candidates.select { |candidate| terms.satisfied_by?(candidate.content) }
                           .map { |candidate| [ candidate, terms.coverage(candidate.content) ] }
                           .select { |_, coverage| coverage.positive? }
                           .sort_by { |candidate, coverage| [ -coverage, candidate.id ] }
        return unanswered(scope, candidates, reasoning: thin_evidence_reason(candidates)) if ranked.empty?

        best = ranked.first.last
        supporting = ranked.select { |_, coverage| coverage >= best * SUPPORTING_COVERAGE_RATIO }
                           .first(MAX_SUPPORTING_CHUNKS)

        coverage = coverage_for(terms, supporting)
        return unanswered(scope, candidates, coverage: coverage, reasoning: weak_reason(coverage)) if coverage < answerable_threshold

        Answer.new(
          answerable: true,
          text: quoted_answer(terms, quotable(supporting, best)),
          coverage: coverage,
          chunk_ids: supporting.map { |candidate, _| candidate.id },
          reasoning: reasoning_for(terms, supporting),
          candidates: candidates,
          scope: scope
        )
      end

      private
        def answerable_threshold = ANSWERABLE_COVERAGE * COVERAGE_SCALE

        # Coverage is measured over the supporting passages together, so an
        # answer split across two chunks still counts as one answer.
        def coverage_for(terms, supporting)
          combined = terms.coverage(supporting.map { |candidate, _| candidate.content }.join(" "))
          bonus = supporting.first.first.both? ? BOTH_METHODS_BONUS : 0.0
          ((combined * COVERAGE_SCALE) + bonus).clamp(0.0, 0.99).round(2)
        end

        # Passages worth quoting: the best one, anything else from the same page
        # as the best one, and anything that nearly matches it.
        def quotable(supporting, best)
          page_id = supporting.first.first.page_id

          supporting.select do |candidate, coverage|
            candidate.page_id == page_id || coverage >= best * QUOTABLE_COVERAGE_RATIO
          end
        end

        def quoted_answer(terms, supporting)
          supporting.flat_map { |candidate, _| terms.best_sentences(candidate.chunk.body, limit: 2) }
                    .uniq
                    .first(4)
                    .join(" ")
                    .squish
        end

        def reasoning_for(terms, supporting)
          matched = terms.matched(supporting.map { |candidate, _| candidate.content }.join(" "))
          sources = supporting.map { |candidate, _| PageTypes.label(candidate.page_type) }.uniq
          "Matched #{matched.size} of #{terms.list.size} question terms across #{supporting.size} " \
            "#{'passage'.pluralize(supporting.size)} in #{sources.to_sentence}."
        end

        def thin_evidence_reason(candidates)
          "Retrieved #{candidates.size} #{'passage'.pluralize(candidates.size)}, none of which mentioned the question's terms."
        end

        def weak_reason(coverage)
          "The closest public passages cover only part of the question (#{(coverage * 100).round}% covered)."
        end
    end
  end
end
