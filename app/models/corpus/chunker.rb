# frozen_string_literal: true

module Corpus
  # Splits a page into retrievable pieces along headings and paragraph
  # boundaries, never mid-sentence, and carries provenance onto every piece.
  #
  # Losing the source URL would make a finding uncitable, so the URL, title,
  # page type, corpus and heading travel with the text instead of being looked
  # up again later.
  #
  #   Corpus::Chunker.new(page).pieces
  #
  class Chunker
    Piece = Data.define(:content, :position, :token_count, :heading, :metadata) do
      def to_attributes = { content: content, position: position, token_count: token_count, metadata: metadata }
    end

    Section = Struct.new(:heading, :body)

    def initialize(page, target_tokens: nil, overlap_tokens: nil)
      @page = page
      @target_tokens = target_tokens || WebsiteIntelligence.config.chunk_target_tokens
      @overlap_tokens = overlap_tokens || WebsiteIntelligence.config.chunk_overlap_tokens
    end

    def pieces
      @pieces ||= sections.flat_map { |section| pieces_for(section) }
                          .each_with_index
                          .map { |piece, index| piece.with(position: index) }
    end

    private
      attr_reader :page, :target_tokens, :overlap_tokens

      # Markdown headings are the most reliable logical boundary a
      # documentation page gives us.
      def sections
        result = []
        current = Section.new(nil, +"")

        page.content.to_s.each_line do |line|
          if (heading = line[/\A\s{0,3}\#{1,6}\s+(.+?)\s*\#*\s*\z/, 1])
            result << current if current.body.strip.present?
            current = Section.new(heading.strip, +"")
          else
            current.body << line
          end
        end

        result << current if current.body.strip.present?
        result.presence || [ Section.new(nil, page.content.to_s) ]
      end

      def pieces_for(section)
        paragraphs = section.body.split(/\n{2,}/).map(&:strip).reject(&:blank?)
        return [] if paragraphs.empty?

        result = []
        buffer = []
        buffer_tokens = 0

        paragraphs.each do |paragraph|
          paragraph_tokens = TokenCount.of(paragraph)

          if buffer.any? && buffer_tokens + paragraph_tokens > target_tokens
            result << build(section, buffer)
            buffer = overlap_from(buffer)
            buffer_tokens = buffer.sum { |part| TokenCount.of(part) }
          end

          # A paragraph larger than the whole target is split on sentence
          # boundaries rather than emitted as one oversized piece.
          if paragraph_tokens > target_tokens
            split(paragraph).each do |sentence_group|
              result << build(section, buffer + [ sentence_group ])
              buffer = []
              buffer_tokens = 0
            end
          else
            buffer << paragraph
            buffer_tokens += paragraph_tokens
          end
        end

        result << build(section, buffer) if buffer.any?
        result
      end

      def split(paragraph)
        groups = []
        buffer = []

        paragraph.split(/(?<=[.!?])\s+/).each do |sentence|
          buffer << sentence
          if TokenCount.of(buffer.join(" ")) >= target_tokens
            groups << buffer.join(" ")
            buffer = []
          end
        end

        groups << buffer.join(" ") if buffer.any?
        groups
      end

      # Trailing text repeats into the next piece, so an answer that straddles a
      # boundary is still retrievable from one piece.
      def overlap_from(buffer)
        overlap = []
        tokens = 0

        buffer.reverse_each do |paragraph|
          paragraph_tokens = TokenCount.of(paragraph)

          if tokens + paragraph_tokens <= overlap_tokens
            overlap.unshift(paragraph)
            tokens += paragraph_tokens
          else
            # A paragraph too long to repeat whole still contributes its tail.
            # Documentation paragraphs are routinely larger than the overlap
            # budget, and without this there would be no overlap at all.
            tail = trailing_sentences(paragraph, overlap_tokens - tokens)
            overlap.unshift(tail) if tail.present?
            break
          end
        end

        overlap
      end

      def trailing_sentences(paragraph, budget)
        return nil if budget <= 0

        taken = []
        paragraph.split(/(?<=[.!?])\s+/).reverse_each do |sentence|
          break if TokenCount.of((taken + [ sentence ]).join(" ")) > budget

          taken.unshift(sentence)
        end

        taken.join(" ").presence
      end

      def build(section, parts)
        body = parts.join("\n\n").strip
        # The page title travels into every chunk. Without it, "Handling a 429
        # response" is unfindable from "API rate limits", because the words that
        # say what the page is about live in a heading the section does not own.
        context = [ page.title, section.heading ].compact_blank.uniq.join(" -- ")
        content = context.present? ? "#{context}\n\n#{body}" : body

        Piece.new(
          content: content,
          position: 0,
          token_count: TokenCount.of(content),
          heading: section.heading,
          metadata: {
            "url" => page.url,
            "canonical_url" => page.canonical_url,
            "title" => page.title,
            "page_type" => page.page_type,
            "corpus_type" => page.corpus_type,
            "heading" => section.heading,
            "context" => context.presence,
            "host" => page.host
          }.compact
        )
      end
  end
end
