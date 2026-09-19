# frozen_string_literal: true

module Corpus
  # Reduces a fetched document to the plain text the pipeline reads.
  #
  # Crawled content is untrusted input, so everything that could be interpreted
  # as markup -- or rendered as markup later -- is flattened here rather than at
  # display time.
  class Cleaner
    HTML_COMMENT = /<!--.*?-->/m
    SCRIPT_OR_STYLE = %r{<(script|style)\b[^>]*>.*?</\1>}mi
    HTML_TAG = /<[^>]+>/
    IMAGE_MARKDOWN = /!\[[^\]]*\]\([^)]*\)/
    LINK_MARKDOWN = /\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/

    def initialize(raw)
      @raw = raw.to_s
    end

    def text
      @text ||= begin
        text = @raw.dup
        text.gsub!(SCRIPT_OR_STYLE, " ")
        text.gsub!(HTML_COMMENT, " ")
        text.gsub!(IMAGE_MARKDOWN, " ")
        # Keep the anchor text, drop the target: inside a chunk the words are
        # the content and the URL is noise.
        text.gsub!(LINK_MARKDOWN) { Regexp.last_match(1) }
        text.gsub!(HTML_TAG, " ")
        text.gsub!(/\r\n?/, "\n")
        text.gsub!(/[ \t]+/, " ")
        # Indentation left by stripped markup would otherwise survive as a
        # leading space on every line.
        text.gsub!(/[ \t]*\n[ \t]*/, "\n")
        text.gsub!(/\n{3,}/, "\n\n")
        text.strip
      end
    end

    def word_count = text.split(/\s+/).count

    # Two URLs serving the same words are one page, whatever their whitespace.
    def digest = Digest::SHA256.hexdigest(text.gsub(/\s+/, " ").strip)
  end
end
