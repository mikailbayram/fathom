require "test_helper"

# The chatbot answering a question is the only paid call a person sits and
# waits on, and it used to be the only one that did not go through Client --
# so it was billed by the aggregator and recorded at no cost, which is how a
# budget stops applying without anyone noticing.
class AI::ResponderLiveTest < ActiveSupport::TestCase
  LIVE = { "APP_MODE" => "live", "ENABLE_LIVE_AI" => "true" }.freeze
  ROUTED = AI::Models::Model.new(role: :chat, id: "openai/gpt-6-luna", provider: :openrouter, effort: :low)

  setup do
    @scan = acme_scan
    @chatbot = Chatbot.create!(scan: @scan, name: "Acme", slug: Chatbot.generate_slug("acme.test"))
    @conversation = @chatbot.conversations.create!(session_id: SecureRandom.uuid)
  end

  ANSWER = { "reply" => "Acme retries a webhook six times.", "used_source_ids" => [], "offer_handoff" => false }.freeze

  def provider_reply(payload)
    Object.new.tap do |message|
      message.define_singleton_method(:content) { payload.to_json }
      message.define_singleton_method(:parsed) { payload }
    end
  end

  def chat_double(options: nil, tools: nil, chunks: [], payload: ANSWER)
    Object.new.tap do |chat|
      asked_for_price = []

      %i[with_instructions with_schema with_thinking].each do |builder|
        chat.define_singleton_method(builder) { |*, **| self }
      end
      chat.define_singleton_method(:with_provider_options) do |given|
        asked_for_price << given if given.dig(:usage, :include)
        options&.push(given)
        self
      end
      chat.define_singleton_method(:with_tools) do |*given|
        tools&.concat(given)
        self
      end
      # An aggregator reports what it charged only when it was asked to, and
      # prices nothing when it was not. Simulated rather than assumed, because a
      # double that always reports a cost cannot tell the fix from the bug.
      chat.define_singleton_method(:tokens) { nil }
      chat.define_singleton_method(:cost) do
        next nil if asked_for_price.empty?

        Object.new.tap { |cost| cost.define_singleton_method(:total) { 0.0042 } }
      end
      answer = provider_reply(payload)
      chat.define_singleton_method(:ask) do |*, &block|
        chunks.each { |fragment| block&.call(fragment) }
        answer
      end
    end
  end

  def chunk(content, finish_reason: nil)
    Object.new.tap do |fragment|
      fragment.define_singleton_method(:content) { content }
      fragment.define_singleton_method(:finish_reason) { finish_reason }
    end
  end

  def responder = AI::Responder::Live.new(@chatbot, conversation: @conversation, model: ROUTED)

  def answering(options: nil, tools: nil, chunks: [], &)
    with_env(LIVE) do
      with_stub(RubyLLM, :chat, ->(**) { chat_double(options: options, tools: tools, chunks: chunks) }, &)
    end
  end

  test "records what the answer cost, from what the provider reported" do
    answering { responder.reply("How many times does Acme retry a webhook?") }

    usage = AIUsage.where(operation: "chat_answer").last

    assert_equal 0.0042, usage.estimated_cost.to_f
    assert_equal @scan, usage.scan
    assert_equal @conversation, usage.conversation
  end

  # Unpriced calls are counted against the scan, and past SpendingLimit's
  # tolerance of five the budget can no longer be enforced -- so every later
  # question is refused before it is sent. A demo that answered five questions
  # and then broke for good is what this costs when it is wrong.
  test "asks the aggregator for the price, so the answer is not recorded as free" do
    options = []

    answering(options: options) do
      6.times { responder.reply("How many times does Acme retry a webhook?") }
    end

    assert_equal [ { usage: { include: true } } ], options.uniq
    assert_empty AIUsage.where(operation: "chat_answer").unpriced
    assert_equal 6, AIUsage.where(operation: "chat_answer").count
  end

  test "gives the model the corpus search" do
    tools = []
    answering(tools: tools) { responder.reply("How many times does Acme retry a webhook?") }

    assert_equal [ AI::Responder::CorpusSearchTool ], tools.map(&:class)
  end

  test "hands over the reply as it is written" do
    written = []
    chunks = [ chunk('{"reply":"Acme retries'), chunk(' a webhook six times."') ]

    answering(chunks: chunks) do
      responder.reply("How many times does Acme retry a webhook?") { |text| written << text }
    end

    assert_equal [ "Acme retries", "Acme retries a webhook six times." ], written
  end

  test "withdraws a reply the model abandoned to go and search" do
    chunks = [ chunk('{"reply":"Let me check'), chunk("", finish_reason: :tool_calls), chunk('{"reply":"Six times.') ]
    written = []

    answering(chunks: chunks) do
      responder.reply("How many times does Acme retry a webhook?") { |text| written << text }
    end

    assert_equal [ "Let me check", "", "Six times." ], written
  end
end
