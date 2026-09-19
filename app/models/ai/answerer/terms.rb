# frozen_string_literal: true

module AI
  class Answerer
    # The significant terms of a question, and how much of them a passage covers.
    #
    # Technical terms weigh double: a passage that mentions SCIM is far better
    # evidence for a SCIM question than one that happens to share the word
    # "support".
    class Terms
      STOPWORDS = %w[
        a an the and or but if of to in on for with without from by at as is are
        was were be been being do does did can could should would will shall may
        it its this that these those you your we our they their what which when
        how does customers customer use used using there here about into than
        rather only other some any each per via not no yes
      ].to_set.freeze

      TECHNICAL_WEIGHT = 2.0
      ORDINARY_WEIGHT = 1.0

      attr_reader :list

      def initialize(question)
        @question = question.to_s
        @list = extract
      end

      def total_weight = @total_weight ||= list.sum { |term| weight(term) }

      # 0.0-1.0: the share of the question's meaning a passage actually covers.
      def coverage(passage)
        return 0.0 if total_weight.zero?

        haystack = passage.to_s.downcase
        matched = list.select { |term| haystack.include?(term) }
        matched.sum { |term| weight(term) } / total_weight
      end

      # Named third-party systems are not interchangeable. A question about
      # NetSuite is not answered by a page about Snowflake, however similar the
      # surrounding wording is, so these terms must be present or the passage is
      # not evidence at all.
      def required
        @required ||= list.select { |term| Lexicon::INTEGRATIONS.any? { |name| name.downcase == term } }
      end

      def satisfied_by?(passage)
        return true if required.empty?

        haystack = passage.to_s.downcase
        required.all? { |term| haystack.include?(term) }
      end

      def matched(passage)
        haystack = passage.to_s.downcase
        list.select { |term| haystack.include?(term) }
      end

      # The sentences of a passage that carry the most of the question, which is
      # what a grounded answer should quote.
      def best_sentences(passage, limit: 3)
        passage.to_s
               .split(/(?<=[.!?])\s+/)
               .map(&:strip)
               .reject(&:blank?)
               .map { |sentence| [ sentence, coverage(sentence) ] }
               .select { |_, score| score.positive? }
               .sort_by { |sentence, score| [ -score, passage.index(sentence) || 0 ] }
               .first(limit)
               .sort_by { |sentence, _| passage.index(sentence) || 0 }
               .map(&:first)
      end

      private
        # A crude singular fold. Without it a page saying "certification" does
        # not answer a question asking about "certifications", which is not a
        # distinction any reader would make.
        def present?(haystack, term)
          return true if haystack.include?(term)

          singular = term.sub(/(?:ies)\z/, "y").sub(/(?:es|s)\z/, "")
          singular.length >= 4 && singular != term && haystack.include?(singular)
        end

        def extract
          words = @question.downcase.scan(/[a-z0-9][a-z0-9_.-]*/)
                           .reject { |word| STOPWORDS.include?(word) || word.length < 3 }
                           .uniq
          # Adjacent pairs catch phrases whose parts are individually common:
          # "custom roles", "data residency", "rate limits".
          words + words.each_cons(2).map { |pair| pair.join(" ") }
        end

        def weight(term) = Lexicon.technical?(term) ? TECHNICAL_WEIGHT : ORDINARY_WEIGHT
    end
  end
end
