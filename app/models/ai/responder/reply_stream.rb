# frozen_string_literal: true

module AI
  class Responder
    # The visible part of a structured answer, read while it is still arriving.
    #
    # The model replies with a JSON object -- the prose beside the source ids it
    # used -- so there is no plain text stream to hand straight to the visitor.
    # What there is instead is a well-known property, declared first in the
    # schema and therefore written first, whose value is exactly the prose. This
    # decodes the prefix of that one string as the bytes come in.
    #
    # It deliberately never parses the object. A half-written object is not
    # JSON, and waiting for it to close is waiting for the whole answer, which
    # is the thing streaming exists to avoid.
    class ReplyStream
      FIELD = '"reply"'

      # The JSON escapes that stand for a single character. \u is handled
      # separately because it is the only one with a payload.
      ESCAPES = { '"' => '"', "\\" => "\\", "/" => "/", "b" => "\b", "f" => "\f",
                  "n" => "\n", "r" => "\r", "t" => "\t" }.freeze

      HIGH_SURROGATES = 0xD800..0xDBFF
      LOW_SURROGATES = 0xDC00..0xDFFF

      # The decoded reply so far. Empty until the property's opening quote has
      # arrived.
      attr_reader :text

      def initialize = reset

      # Takes the next fragment of raw response text and returns the decoded
      # reply so far when it grew, or nil when this fragment added nothing a
      # reader could see -- a key, a delimiter, half of an escape sequence.
      def <<(fragment)
        @raw << fragment.to_s
        decode
      end

      # Ends the object being written and starts a new one.
      #
      # A round that finishes in a tool call abandons whatever it had begun to
      # say; the answer is written from the top once the search comes back. Text
      # emitted before that belongs to a reply that no longer exists.
      def reset
        @raw = +""
        @text = +""
        @value_start = nil
        self
      end

      private
        def decode
          start = value_start or return nil

          decoded = +""
          cursor = start
          while cursor < @raw.length
            character = @raw[cursor]
            break if character == '"' # the value closed; the rest is the object

            if character == "\\"
              literal, width = unescape(cursor)
              break if literal.nil? # an escape sequence cut in half by the wire
              decoded << literal
              cursor += width
            else
              decoded << character
              cursor += 1
            end
          end

          return nil if decoded == @text

          @text = decoded
        end

        # The offset just past the opening quote of the reply's value, or nil
        # while the property has not fully arrived. Memoised: it cannot move.
        def value_start
          return @value_start if @value_start

          key = @raw.index(FIELD) or return nil
          cursor = skip_space(key + FIELD.length)
          return nil unless @raw[cursor] == ":"

          cursor = skip_space(cursor + 1)
          return nil unless @raw[cursor] == '"'

          @value_start = cursor + 1
        end

        def skip_space(cursor)
          cursor += 1 while @raw[cursor]&.match?(/\s/)
          cursor
        end

        # The character an escape sequence at +cursor+ stands for, with how much
        # raw text it occupied, or nil when not all of it has arrived yet.
        def unescape(cursor)
          code = @raw[cursor + 1] or return nil
          return [ ESCAPES.fetch(code), 2 ] if ESCAPES.key?(code)
          return [ code, 2 ] unless code == "u" # not an escape we know; keep it literal

          point = code_point(cursor) or return nil
          return [ "", 6 ] if LOW_SURROGATES.cover?(point) # a stray half; nothing to show

          return [ point.chr(Encoding::UTF_8), 6 ] unless HIGH_SURROGATES.cover?(point)

          paired(cursor, point)
        end

        # A character outside the basic plane arrives as two escapes, and half of
        # one is not a character. Emitting it alone would put an invalid byte
        # sequence into the reply and take the rest of the page with it.
        def paired(cursor, high)
          return nil unless @raw[cursor + 6, 2] == "\\u"

          low = code_point(cursor + 6) or return nil
          return [ "", 6 ] unless LOW_SURROGATES.cover?(low)

          [ (0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)).chr(Encoding::UTF_8), 12 ]
        end

        def code_point(cursor)
          digits = @raw[cursor + 2, 4]
          return nil if digits.nil? || digits.length < 4 || !digits.match?(/\A\h{4}\z/)

          digits.hex
        end
    end
  end
end
