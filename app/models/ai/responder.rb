# frozen_string_literal: true

module AI
  # The chatbot's answer to a visitor's question, grounded in exactly one
  # scan's indexed corpus.
  #
  #   AI::Responder.build(chatbot).reply("Does Acme support custom RBAC?")
  #
  # It uses the same retrieval as findings analysis, so what the chatbot tells a
  # lead and what the findings claim are the same claim.
  class Responder
    Reply = Data.define(:content, :sources, :grounded, :kind, :chunk_ids) do
      def initialize(content:, sources: [], grounded: false, kind: "answer", chunk_ids: []) = super

      def grounded? = grounded

      # chunk_ids are kept so a follow-up can stay anchored to the passages the
      # previous answer actually used.
      def to_metadata = { "grounded" => grounded, "sources" => sources, "kind" => kind, "chunk_ids" => chunk_ids }
    end

    def self.build(chatbot, conversation: nil)
      klass = WebsiteIntelligence.live_ai_enabled? ? Live : Fake
      klass.new(chatbot, conversation: conversation)
    end

    # How much of the thread the model sees. Enough for follow-ups to resolve,
    # short enough that a long demo does not quietly become an expensive one.
    HISTORY_TURNS = 6

    def initialize(chatbot, conversation: nil, model: Models.chat, search: nil)
      @chatbot = chatbot
      @conversation = conversation
      @model = model
      @search = search || Corpus::Search.new(chatbot.scan)
    end

    # The deterministic path. Live overrides this wholesale and lets the model
    # decide; this exists so fake mode behaves predictably without one.
    def reply(message)
      case Intent.of(message)
      when :empty then meta_reply
      when :greeting then greeting_reply
      when :meta then meta_reply
      when :overview then overview_reply
      when :human then human_reply
      when :smalltalk then smalltalk_reply
      else answer(message)
      end
    end

    def answer(_question) = raise NotImplementedError

    private
      attr_reader :chatbot, :conversation, :model, :search

      def company = chatbot.scan.lead.name

      # A sales engineer who does not know something says what they do know and
      # where to go next. They do not repeat one sentence about a documentation
      # index. Which of these applies is decided by what retrieval actually
      # found, so the reply is never a guess dressed up as helpfulness.
      def unavailable(question, candidates = [])
        # Nothing retrieved because nothing is indexed is a fact about us, not
        # about the question. Saying "that's outside what I can help with" to a
        # perfectly good question is how the demo insulted its own visitor.
        return nothing_indexed if candidates.empty?
        return off_topic if off_topic?(question, candidates)

        near = candidates.first(2).uniq(&:source_url)
        Reply.new(
          content: "#{company} doesn't state that anywhere I can find in their public documentation. " \
                   "The closest I have is #{near.map { |c| PageTypes.label(c.page_type).downcase }.uniq.to_sentence}, " \
                   "which covers #{near.map { |c| c.heading.presence || c.source_title }.compact.uniq.to_sentence}. " \
                   "For something this specific their team would be the faster route.",
          sources: sources_from(near, near.map(&:id)),
          kind: "unavailable"
        )
      end

      # Someone on this page is asking about this company. Off-topic is a rare
      # exception, not the default for anything that fails to name it -- the
      # earlier rule declined "what do you guys do?", which is the single most
      # common opening question there is.
      #
      # So the bar is deliberately high: the question has to be substantial and
      # share essentially nothing with anything the company published.
      OFF_TOPIC_COVERAGE = 0.08

      # Someone being friendly gets a friendly answer and a way forward, not a
      # statement about the boundaries of the corpus.
      def smalltalk_reply
        Reply.new(content: "Happy to help. Ask me anything about #{company} -- how something works, what a plan " \
                           "includes, how they handle security -- and I'll pull it from their own pages.",
                  kind: "smalltalk")
      end

      # Someone asking for a person gets one, not a refusal. The reply is what
      # opens the handoff form, so the question they actually care about reaches
      # a human who can answer it.
      def human_reply
        Reply.new(
          content: "Of course. Leave your email and I'll pass you to #{company}'s team along with what " \
                   "you've asked here, so you don't have to repeat yourself.",
          kind: "human_requested"
        )
      end

      # What the company does, from the profile the scan already built out of
      # their own pages. This is the opening question of most conversations and
      # it deserves an answer, not a redirect.
      def overview_reply
        profile = chatbot.scan.company_profile
        return unavailable_overview if profile.nil? || profile.description.blank?

        parts = [ profile.description.squish ]
        if profile.named_integrations.any?
          parts << "They integrate with #{profile.named_integrations.first(4).to_sentence}."
        end
        parts << "Ask me anything more specific and I'll pull it from their documentation."

        Reply.new(content: parts.join(" "), sources: overview_sources, grounded: true, kind: "overview")
      end

      def unavailable_overview
        Reply.new(content: "I have #{company}'s public pages indexed but no clear description of what they do." \
                           "#{topic_hint}",
                  kind: "unavailable")
      end

      # Cited to the pages the description was drawn from.
      def overview_sources
        chunk = chatbot.scan.chunks
                       .where(corpus_type: CorpusTypes::BUYER_VISIBLE)
                       .order(:page_id, :position)
                       .first
        return [] if chunk.nil?

        [ { "title" => chunk.source_title.presence || "Overview", "url" => chunk.source_url,
            "page_type" => chunk.page_type, "page_type_label" => PageTypes.label(chunk.page_type),
            "excerpt" => chunk.excerpt(limit: 240) } ]
      end

      def off_topic?(question, candidates)
        terms = Answerer::Terms.new(question)
        return false if terms.list.size < 3

        candidates.map { |candidate| terms.coverage(candidate.content) }.max.to_f < OFF_TOPIC_COVERAGE
      end

      # Someone being friendly gets a friendly answer and a way forward, not a
      # statement about the boundaries of the corpus.
      def smalltalk_reply
        Reply.new(content: "Happy to help. Ask me anything about #{company} -- how something works, what a plan " \
                           "includes, how they handle security -- and I'll pull it from their own pages.",
                  kind: "smalltalk")
      end

      # Someone asking for a person gets one, not a refusal. The reply is what
      # opens the handoff form, so the question they actually care about reaches
      # a human who can answer it.
      def human_reply
        Reply.new(
          content: "Of course. Leave your email and I'll pass you to #{company}'s team along with what " \
                   "you've asked here, so you don't have to repeat yourself.",
          kind: "human_requested"
        )
      end

      # What the company does, from the profile the scan already built out of
      # their own pages. This is the opening question of most conversations and
      # it deserves an answer, not a redirect.
      def overview_reply
        profile = chatbot.scan.company_profile
        return unavailable_overview if profile.nil? || profile.description.blank?

        parts = [ profile.description.squish ]
        if profile.named_integrations.any?
          parts << "They integrate with #{profile.named_integrations.first(4).to_sentence}."
        end
        parts << "Ask me anything more specific and I'll pull it from their documentation."

        Reply.new(content: parts.join(" "), sources: overview_sources, grounded: true, kind: "overview")
      end

      def unavailable_overview
        Reply.new(content: "I have #{company}'s public pages indexed but no clear description of what they do." \
                           "#{topic_hint}",
                  kind: "unavailable")
      end

      # Cited to the pages the description was drawn from.
      def overview_sources
        chunk = chatbot.scan.chunks
                       .where(corpus_type: CorpusTypes::BUYER_VISIBLE)
                       .order(:page_id, :position)
                       .first
        return [] if chunk.nil?

        [ { "title" => chunk.source_title.presence || "Overview", "url" => chunk.source_url,
            "page_type" => chunk.page_type, "page_type_label" => PageTypes.label(chunk.page_type),
            "excerpt" => chunk.excerpt(limit: 240) } ]
      end

      def nothing_indexed
        Reply.new(content: "I don't have enough of #{company}'s site indexed to answer that reliably, and I would " \
                           "rather say so than guess. Their team can answer it directly.",
                  kind: "nothing_indexed")
      end

      def off_topic
        Reply.new(content: "That's outside what I can help with -- I only know #{company}'s public website and " \
                           "documentation.#{topic_hint}",
                  kind: "off_topic")
      end

      def greeting_reply
        Reply.new(content: "Hello. Ask me anything about #{company} and I'll answer from their public " \
                           "website and documentation, with a link to the page it came from.#{topic_hint}",
                  kind: "greeting")
      end

      # What it can talk about comes from what the scan actually found, not from
      # a canned list.
      def meta_reply
        Reply.new(content: "I answer questions about #{company} using only their own public website and " \
                           "documentation. I show the source for every answer, and I'll tell you plainly " \
                           "when something isn't covered there.#{topic_hint}",
                  kind: "meta")
      end

      def topic_hint
        topics = chatbot.scan.claims.where.not(topic: nil).distinct.limit(6).pluck(:topic).compact
        return "" if topics.empty?

        " Their documentation covers things like #{topics.first(4).to_sentence}."
      end

      # The recent thread, oldest first, as plain turns.
      def history
        return [] if conversation.nil?

        conversation.messages.last(HISTORY_TURNS).map { |message| [ message.role, message.content ] }
      end

      # A follow-up like "and which plan?" is not a searchable query on its own.
      # Pairing it with the last thing the visitor asked is enough to retrieve
      # against, and costs nothing.
      def follow_up?(question) = question.to_s.split.size <= 6 && history.any?

      def search_query(question)
        return question unless follow_up?(question)

        previous = history.reverse.find { |role, _| role == "user" }&.last
        previous.blank? ? question : "#{previous} #{question}"
      end

      # The passages the previous answer used. A follow-up belongs to the thing
      # just discussed; without this, "and which plan?" wanders off and answers
      # about whatever else on the site happens to mention a plan.
      def anchor_page_ids
        return [] if conversation.nil?

        ids = conversation.messages.where(role: "assistant").last&.metadata&.dig("chunk_ids")
        Chunk.where(id: Array(ids)).distinct.pluck(:page_id)
      end

      def anchored(candidates, question)
        return candidates unless follow_up?(question)

        pages = anchor_page_ids
        return candidates if pages.empty?

        candidates.select { |candidate| pages.include?(candidate.chunk.page_id) }.presence || candidates
      end

      # Only the chunks that actually supported the answer become sources, and
      # every source carries the public URL a reader can open for themselves.
      #
      # Deduplicated by URL: three passages from one page are one source to a
      # reader, and listing the same link three times reads like a bug.
      def sources_from(candidates, chunk_ids)
        candidates.select { |candidate| chunk_ids.include?(candidate.id) }
                  .uniq(&:source_url)
                  .map do |candidate|
          {
            "title" => candidate.source_title.presence || candidate.heading.presence || "Source",
            "url" => candidate.source_url,
            "page_type" => candidate.page_type,
            "page_type_label" => PageTypes.label(candidate.page_type),
            "excerpt" => candidate.chunk.excerpt(limit: 240)
          }
        end
      end
  end
end
