require "test_helper"

# An embedded widget is a third-party iframe: the browser sends no cookie with
# anything it does. Everything that identifies the visitor has to travel on the
# request itself, or each message lands in a conversation of its own and the
# answer is broadcast to a socket nobody is listening on.
class WidgetVisitorTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    scan = Scan.start!(Lead.for_website("https://acme.test"))
    @chatbot = scan.create_chatbot!(name: "Acme", slug: "acme-#{SecureRandom.hex(3)}",
                                    public: true, status: "active")
    @visitor = SecureRandom.uuid
  end

  test "the paths the demo posts to carry the visitor token" do
    get public_demo_path(@chatbot.slug, v: @visitor)

    assert_response :success
    props = inertia.props

    assert_includes props[:ask_path], "v=#{@visitor}"
    assert_includes props[:handoff_path], "v=#{@visitor}"
    assert_equal @visitor, props[:visitor]
  end

  test "a message posted with the token joins the conversation the page opened" do
    get public_demo_path(@chatbot.slug, v: @visitor)
    opened = Conversation.find_by!(chatbot: @chatbot, session_id: @visitor)

    assert_no_difference -> { @chatbot.conversations.count } do
      post public_demo_messages_path(@chatbot.slug, v: @visitor), params: { question: "Do you support SSO?" }
    end

    assert_equal opened.id, @chatbot.conversations.sole.id
    assert_equal "Do you support SSO?", opened.messages.order(:id).last.content
  end

  test "a message from nobody is refused rather than answered in a new thread" do
    # The regression this guards. Quietly minting a visitor here is what let the
    # widget talk to a conversation nobody was subscribed to, in silence.
    assert_no_difference -> { Conversation.count } do
      post public_demo_messages_path(@chatbot.slug), params: { question: "First" }
    end

    assert_response :bad_request
  end

  test "the header identifies a request that carries no cookie and no token" do
    get public_demo_path(@chatbot.slug, v: @visitor)
    opened = Conversation.find_by!(chatbot: @chatbot, session_id: @visitor)

    assert_no_difference -> { Conversation.count } do
      post public_demo_messages_path(@chatbot.slug),
           params: { question: "Do you support SSO?" },
           headers: { VisitorSession::VISITOR_HEADER => @visitor }
    end

    assert_response :created
    assert_equal "Do you support SSO?", opened.messages.order(:id).last.content
  end

  test "a question survives having no session cookie, as a third-party iframe has none" do
    # The authenticity token is derived from the session, and an embedded
    # widget never gets one. Before this, every widget question was refused as
    # a forgery before it reached the controller.
    get public_demo_path(@chatbot.slug, v: @visitor)
    reset!

    post public_demo_messages_path(@chatbot.slug),
         params: { question: "Do you support SSO?" },
         headers: { VisitorSession::VISITOR_HEADER => @visitor }

    assert_response :created
    assert_equal @visitor, @chatbot.conversations.sole.session_id
  end

  test "a handoff is identified the same way" do
    get public_demo_path(@chatbot.slug, v: @visitor)

    post public_demo_handoffs_path(@chatbot.slug),
         params: { question: "Do you support SSO?", email: "buyer@example.com" },
         headers: { VisitorSession::VISITOR_HEADER => @visitor }

    assert_response :success
    assert_equal 1, @chatbot.handoffs.count
  end

  test "a widget may ask its first question with a token it minted itself" do
    token = SecureRandom.uuid

    post public_demo_messages_path(@chatbot.slug),
         params: { question: "Do you support SSO?" },
         headers: { VisitorSession::VISITOR_HEADER => token }

    assert_response :created
    assert_equal token, @chatbot.conversations.sole.session_id
  end

  test "the answer is broadcast to the conversation the widget is subscribed to" do
    get public_demo_path(@chatbot.slug, v: @visitor)
    conversation = Conversation.find_by!(chatbot: @chatbot, session_id: @visitor)

    assert_broadcasts(ConversationChannel.broadcasting_for(conversation), 1) do
      post public_demo_messages_path(@chatbot.slug, v: @visitor), params: { question: "Do you support SSO?" }
      perform_enqueued_jobs_until_idle(limit: 20)
    end
  end
end
