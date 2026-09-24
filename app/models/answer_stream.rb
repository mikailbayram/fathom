# frozen_string_literal: true

# An answer on its way to the visitor, before it is a record.
#
# A model writes far faster than anything needs to be read, and every push here
# is a row in the cable table that every open subscriber polls for. So the reply
# goes out on a fixed cadence rather than per token: pushing is cheap and
# broadcasting is not.
#
# What is sent is always the whole reply so far, never the difference. A poll
# that coalesces two broadcasts then loses nothing, a subscriber that joins
# halfway is not left with a hole, and a reply the model abandoned after a
# search is undone by sending a shorter text rather than by an instruction the
# client has to understand. The sequence number is what lets a client tell a
# rewrite from a delivery that arrived out of order.
class AnswerStream
  # Slower than a model emits tokens, faster than a reader can notice. Below the
  # cable's own polling interval there is nothing to gain: the broadcasts would
  # simply queue and arrive together.
  INTERVAL = 0.12

  def initialize(conversation, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @conversation = conversation
    @id = SecureRandom.uuid
    @clock = clock
    @seq = 0
    @pending = nil
    @sent_at = nil
  end

  # Records the reply so far, and sends it if enough time has passed. The first
  # push always goes out, so the thinking indicator gives way the moment there
  # is a word to show.
  def push(text)
    @pending = text
    flush if @sent_at.nil? || (@clock.call - @sent_at) >= INTERVAL
  end

  def flush
    return if @pending.nil?

    @seq += 1
    ConversationChannel.broadcast_answer(@conversation, id: @id, seq: @seq, text: @pending)
    @sent_at = @clock.call
    @pending = nil
  end
end
