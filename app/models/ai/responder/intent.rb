# frozen_string_literal: true

module AI
  class Responder
    # A crude read of what a visitor is doing, used *only* in fake mode.
    #
    # Live conversations do not come through here: a language model judges this
    # far better than patterns can, and every pattern added here was a patch for
    # some phrasing that had already embarrassed the product. It survives
    # because fake mode has no model and its behaviour must stay deterministic
    # for the test suite.
    module Intent
      GREETING = /\A\s*(?:hi|hey|hello|yo|good\s+(?:morning|afternoon|evening)|howdy|thanks|thank you|
                        ok(?:ay)?|cool|nice|great|bye|goodbye)\b[\s!.?]*\z/xi

      # About the assistant itself.
      META = /\A\s*who\s+are\s+you\b|
              \bare\s+you\s+(?:a\s+)?(?:bot|ai|human|real)\b|
              \bwhat\s+(?:can|do)\s+(?:you|i)\s+ask\b|
              \bwhat\s+(?:do\s+you\s+)?know\s+about\s+you\b/xi

      # "What do you guys do?" is the first thing anyone asks, and it is a
      # question about the company, not about the assistant. Treating it as
      # off-topic -- which is what happened -- is the worst possible answer.
      OVERVIEW = /\bwhat\s+(?:do|does)\s+(?:you|they|your\s+\w+|the\s+\w+|\w+)\s*(?:guys|team|company|folks)?\s*do\b|
                  \bwhat\s+(?:is|are)\s+(?:this|it|you|your\s+product|your\s+platform)\b|
                  \btell\s+me\s+about\b|
                  \bwhat\s+(?:kind\s+of\s+)?(?:product|company|business|platform|software)\b|
                  \bwho\s+(?:is|are)\s+(?:this|your\s+customers?)\b|
                  \bwhat\s+problem\b|
                  \bhow\s+does\s+(?:it|this|the\s+product)\s+work\b/xi

      # Asking for a person is the clearest buying signal a demo can produce, and
      # declining it is the worst possible answer -- especially in a product that
      # has a handoff built into it.
      HUMAN = /\b(?:talk|speak|chat|connect)\s+(?:to|with)\s+(?:a\s+)?(?:human|person|someone|rep|sales|
                 support|agent|team)\b|
               \b(?:contact|reach|call|email)\s+(?:you|your\s+team|sales|support|someone)\b|
               \bbook\s+(?:a\s+)?(?:demo|call|meeting)\b|
               \b(?:get|put)\s+me\s+(?:in\s+touch|through)\b|
               \bis\s+(?:there|anyone)\s+(?:a\s+)?(?:human|person|someone)\b|
               \bhuman\s+(?:please|support)\b/xi

      # Words that carry warmth but no question.
      SOCIAL = %w[
        thanks thank great nice cool awesome perfect good ok okay sure right wow
        amazing helpful appreciate cheers lovely brilliant excellent yeah yep yes
        no nope please sorry haha lol indeed alright fine fair enough
        work job guys folks stuff mate friend
      ].to_set.freeze

      module_function

      def of(message)
        text = message.to_s.strip
        return :empty if text.blank?
        return :human if text.match?(HUMAN)
        return :greeting if text.match?(GREETING)
        return :meta if text.match?(META)
        return :overview if text.match?(OVERVIEW)
        return :smalltalk if smalltalk?(text)

        :question
      end

      # Small talk is a message with nothing in it but courtesy. Judged by what
      # survives stopword and social-word removal rather than by matching
      # phrases, so it holds for wording nobody predicted -- and it keeps
      # "is your security good?" a question, because "security" survives.
      def smalltalk?(text)
        return false if text.length > 60

        Answerer::Terms.new(text).list.none? { |term| substantive?(term) }
      end

      def substantive?(term)
        term.split.any? { |word| !SOCIAL.include?(word) }
      end
    end
  end
end
