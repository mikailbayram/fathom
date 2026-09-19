require "test_helper"

class AI::ClientTest < ActiveSupport::TestCase
  LIVE = { "APP_MODE" => "live", "ENABLE_LIVE_AI" => "true" }.freeze

  setup { @scan = acme_scan }

  # Stands in for a provider reply: enough of RubyLLM::Message for the client to
  # read the content and record usage it has no numbers for.
  def reply
    Object.new.tap do |message|
      message.define_singleton_method(:content) { "ok" }
      message.define_singleton_method(:tokens) { nil }
      message.define_singleton_method(:cost) { nil }
    end
  end

  # A chat double that rejects its first +failures+ calls the way a metered
  # provider does, then answers.
  def chat_double(calls:, failures: 0, error: nil, thinking: nil)
    Object.new.tap do |chat|
      %i[with_provider_options with_instructions with_schema].each do |builder|
        chat.define_singleton_method(builder) { |*| self }
      end
      chat.define_singleton_method(:with_thinking) do |**options|
        thinking&.push(options)
        self
      end
      answer = reply
      chat.define_singleton_method(:ask) do |*|
        calls << :ask
        raise(error || RubyLLM::RateLimitError, "20 requests per minute") if error || calls.size <= failures

        answer
      end
    end
  end

  def client = AI::Client.new(model: AI::Models.analysis, operation: "claim_extraction", scan: @scan)

  test "waits out a rate limit rather than failing the stage" do
    # Providers meter per minute and stages fan out several calls at once, so a
    # new account meets 429 before it meets anything else. Failing there would
    # discard every passage already read.
    calls = []
    waited = []

    with_env(LIVE) do
      with_stub(AI::Client, :pause, ->(seconds) { waited << seconds }) do
        with_stub(RubyLLM, :chat, ->(**) { chat_double(calls: calls, failures: 2) }) do
          assert_equal "ok", client.text(instructions: "i", prompt: "p")
        end
      end
    end

    assert_equal 3, calls.size, "two rejections, then the call that succeeded"
    assert_equal [ 5, 15 ], waited, "each wait longer than the last"
  end

  test "gives up once the limit has not cleared, and says that is what happened" do
    calls = []

    with_env(LIVE) do
      with_stub(AI::Client, :pause, ->(*) { }) do
        with_stub(RubyLLM, :chat, ->(**) { chat_double(calls: calls, failures: 99) }) do
          error = assert_raises(AI::Client::ResponseError) { client.text(instructions: "i", prompt: "p") }

          assert_match(/rate limited/, error.message)
          assert_match(/claim_extraction/, error.message)
        end
      end
    end

    assert_equal AI::Client::RATE_LIMIT_ATTEMPTS, calls.size
  end

  test "an error that is not a rate limit fails immediately" do
    calls = []

    with_env(LIVE) do
      with_stub(RubyLLM, :chat, ->(**) { chat_double(calls: calls, error: RubyLLM::ServerError) }) do
        error = assert_raises(AI::Client::ResponseError) { client.text(instructions: "i", prompt: "p") }

        assert_match(/failed during claim_extraction/, error.message)
      end
    end

    assert_equal 1, calls.size, "retrying a real failure would only delay it"
  end

  test "asks for the reasoning effort the role carries" do
    calls = []
    thinking = []
    chat = AI::Models::Model.new(role: :chat, id: "gpt-5.6-terra", provider: :openrouter, effort: :medium)

    with_env(LIVE) do
      with_stub(RubyLLM, :chat, ->(**) { chat_double(calls: calls, thinking: thinking) }) do
        AI::Client.new(model: chat, operation: "chat_answer", scan: @scan).text(instructions: "i", prompt: "p")
      end
    end

    assert_equal [ { effort: :medium } ], thinking
  end

  test "says nothing about effort for a role that sets none" do
    # A role with no effort must leave the provider its own default rather than
    # quietly asking for one, which is what every non-chat role expects.
    calls = []
    thinking = []

    with_env(LIVE) do
      with_stub(RubyLLM, :chat, ->(**) { chat_double(calls: calls, thinking: thinking) }) do
        client.text(instructions: "i", prompt: "p")
      end
    end

    assert_empty thinking
  end
end
