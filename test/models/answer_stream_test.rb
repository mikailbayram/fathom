require "test_helper"

# A model writes faster than a reader reads and faster than the cable should be
# asked to carry, so this is about cadence: what gets sent, when, and what is
# quietly dropped because something newer already says it.
class AnswerStreamTest < ActiveSupport::TestCase
  setup do
    @sent = []
    @now = 0.0
  end

  # Records the broadcasts instead of making them. What is under test is when a
  # reply goes out and what it carries, not how a channel delivers it.
  def streaming
    with_stub(ConversationChannel, :broadcast_answer, ->(_conversation, id:, seq:, text:) { @sent << [ id, seq, text ] }) do
      yield AnswerStream.new(:conversation, clock: -> { @now })
    end
  end

  def texts = @sent.map(&:last)

  test "the first word goes out at once, so the thinking dots give way quickly" do
    streaming { |stream| stream.push("Acme") }

    assert_equal [ "Acme" ], texts
  end

  test "holds everything written inside the interval and sends only the newest" do
    streaming do |stream|
      stream.push("Acme")
      @now += AnswerStream::INTERVAL / 2
      stream.push("Acme supports")
      stream.push("Acme supports RBAC")
    end

    assert_equal [ "Acme" ], texts
  end

  test "sends the whole reply so far once the interval has passed" do
    streaming do |stream|
      stream.push("Acme")
      @now += AnswerStream::INTERVAL
      stream.push("Acme supports RBAC")
    end

    assert_equal [ "Acme", "Acme supports RBAC" ], texts
  end

  test "numbers what it sends, under one id, so a client can order them" do
    streaming do |stream|
      stream.push("Acme")
      @now += AnswerStream::INTERVAL
      stream.push("Acme supports RBAC")
    end

    assert_equal [ 1, 2 ], @sent.map { |_id, seq, _text| seq }
    assert_equal 1, @sent.map(&:first).uniq.size
  end

  test "flushing sends what is being held, and nothing when nothing is" do
    streaming do |stream|
      stream.push("Acme")
      stream.push("Acme supports RBAC")
      stream.flush
      stream.flush
    end

    assert_equal [ "Acme", "Acme supports RBAC" ], texts
  end
end
