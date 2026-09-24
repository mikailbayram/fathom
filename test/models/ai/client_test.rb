require "test_helper"

class AI::ClientTest < ActiveSupport::TestCase
  LIVE = { "APP_MODE" => "live", "ENABLE_LIVE_AI" => "true" }.freeze

  setup { @scan = acme_scan }

  # Stands in for a provider reply: enough of RubyLLM::Message for the client to
  # read the content and record usage it has no numbers for.
  def reply
    Object.new.tap do |message|
      message.define_singleton_method(:content) { "ok" }
      message.define_singleton_method(:parsed) { { "ok" => true } }
    end
  end

  # A chat double that rejects its first +failures+ calls the way a metered
  # provider does, then answers. Anything it is configured with is appended to
  # the array given for it, so a test can assert what the provider was told.
  def chat_double(calls:, failures: 0, error: nil, thinking: nil, tools: nil, options: nil, chunks: [])
    Object.new.tap do |chat|
      %i[with_instructions with_schema].each do |builder|
        chat.define_singleton_method(builder) { |*| self }
      end
      chat.define_singleton_method(:with_provider_options) do |given|
        options&.push(given)
        self
      end
      chat.define_singleton_method(:with_tools) do |*given|
        tools&.concat(given)
        self
      end
      chat.define_singleton_method(:with_thinking) do |**given|
        thinking&.push(given)
        self
      end
      # Usage is read from the chat, which aggregates every request it made,
      # rather than from the one reply it returned.
      chat.define_singleton_method(:tokens) { nil }
      chat.define_singleton_method(:cost) { nil }
      answer = reply
      chat.define_singleton_method(:ask) do |*, &block|
        calls << :ask
        raise(error || RubyLLM::RateLimitError, "20 requests per minute") if error || calls.size <= failures

        chunks.each { |chunk| block&.call(chunk) }
        answer
      end
    end
  end

  # One fragment of a streamed response.
  def chunk(content, finish_reason: nil)
    Object.new.tap do |fragment|
      fragment.define_singleton_method(:content) { content }
      fragment.define_singleton_method(:finish_reason) { finish_reason }
    end
  end

  # Records what a stream was told, including being asked to start over.
  def recording_stream
    Object.new.tap do |stream|
      events = []
      stream.define_singleton_method(:events) { events }
      stream.define_singleton_method(:call) { |fragment| events << fragment.content }
      stream.define_singleton_method(:reset) { events << :reset }
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

  test "asks an aggregator to report what it charged" do
    # Model routing skips RubyLLM's registry, so nothing local knows the price
    # and it has to come back with the response. An aggregator only reports it
    # when asked, and a null price is read as a free call by the budget.
    calls = []
    options = []
    routed = AI::Models::Model.new(role: :analysis, id: "openai/gpt-6-sol", provider: :openrouter)

    with_env(LIVE) do
      with_stub(RubyLLM, :chat, ->(**) { chat_double(calls: calls, options: options) }) do
        AI::Client.new(model: routed, operation: "claim_extraction", scan: @scan).text(instructions: "i", prompt: "p")
      end
    end

    assert_equal [ { usage: { include: true } } ], options
  end

  test "hands the model the tools it may call" do
    calls = []
    tools = []
    tool = Object.new

    with_env(LIVE) do
      with_stub(RubyLLM, :chat, ->(**) { chat_double(calls: calls, tools: tools) }) do
        client.structured(schema: { type: "object" }, instructions: "i", prompt: "p", tools: [ tool ])
      end
    end

    assert_equal [ tool ], tools
  end

  test "feeds a given stream every fragment of the reply" do
    calls = []
    stream = recording_stream

    with_env(LIVE) do
      with_stub(RubyLLM, :chat, ->(**) { chat_double(calls: calls, chunks: [ chunk("Two per"), chunk(" minute.") ]) }) do
        client.structured(schema: { type: "object" }, instructions: "i", prompt: "p", stream: stream)
      end
    end

    assert_equal [ "Two per", " minute." ], stream.events
  end

  # The retried request writes its answer again from nothing, so whatever the
  # refused attempt had already shown has to be taken back rather than left on
  # screen for the next attempt to append to.
  test "tells the stream to start over before retrying a refused request" do
    calls = []
    stream = recording_stream

    with_env(LIVE) do
      with_stub(AI::Client, :pause, ->(*) { }) do
        with_stub(RubyLLM, :chat, ->(**) { chat_double(calls: calls, failures: 1, chunks: [ chunk("Two per") ]) }) do
          client.structured(schema: { type: "object" }, instructions: "i", prompt: "p", stream: stream)
        end
      end
    end

    assert_equal [ :reset, "Two per" ], stream.events
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
