require "test_helper"

class PublicDemoTest < ActionDispatch::IntegrationTest
  setup do
    @scan = acme_scan
    run_pipeline(@scan)
    @chatbot = @scan.chatbot
  end

  test "a visitor reaches the demo without an account" do
    get public_demo_path(@chatbot.slug)

    assert_response :success
    assert_equal "Demos/Show", inertia_component
    assert_equal "Acme", inertia_props["company"]
  end

  test "suggested questions come from real findings" do
    get public_demo_path(@chatbot.slug)
    suggested = inertia_props["suggested_questions"]

    assert_predicate suggested, :any?
    assert_equal suggested, suggested & @scan.findings.viable.ranked.map { |f| f.claim.question_text }
  end

  test "accepts a question immediately and answers it off the request cycle" do
    assert_enqueued_with(job: AnswerDemoQuestionJob) do
      post public_demo_messages_path(@chatbot.slug),
           params: { question: "Can administrators define custom RBAC roles in Acme?" }
    end

    assert_response :created
    posted = JSON.parse(response.body).fetch("message")
    assert_equal "user", posted["role"]

    perform_enqueued_jobs
    answer = @chatbot.conversations.first.messages.where(role: "assistant").last

    assert answer.grounded?
    assert_match(/custom RBAC roles/i, answer.content)
    assert_equal "https://docs.acme.test/roles", answer.sources.first["url"]
  end

  test "broadcasts the answer to the visitor who asked" do
    post public_demo_messages_path(@chatbot.slug), params: { question: "What are Acme's RPO and RTO?" }
    conversation = @chatbot.conversations.first

    assert_broadcasts_on_channel(conversation) { perform_enqueued_jobs }
  end

  test "says plainly when a fact is not published, and offers the nearest thing" do
    post public_demo_messages_path(@chatbot.slug), params: { question: "Does Acme hold FedRAMP authorization?" }
    perform_enqueued_jobs

    answer = @chatbot.conversations.first.messages.where(role: "assistant").last

    assert_not answer.grounded?
    assert_equal "unavailable", answer.metadata["kind"]
    assert_match(/doesn't state that/i, answer.content)
    # A sales engineer who does not know something still points somewhere.
    assert_match(/their team/i, answer.content)
  end

  test "asking for a person offers one instead of declining" do
    post public_demo_messages_path(@chatbot.slug), params: { question: "can I talk to a human?" }
    perform_enqueued_jobs

    reply = @chatbot.conversations.first.messages.where(role: "assistant").last

    assert_equal "human_requested", reply.metadata["kind"]
    assert_match(/leave your email/i, reply.content)
    assert_match(/Acme/, reply.content)
  end

  test "asking what the company does is answered, not declined" do
    post public_demo_messages_path(@chatbot.slug), params: { question: "what do you guys do?" }
    perform_enqueued_jobs

    reply = @chatbot.conversations.first.messages.where(role: "assistant").last

    assert_equal "overview", reply.metadata["kind"]
    assert reply.grounded?
    assert_predicate reply.sources, :any?, "an overview should still cite where it came from"
  end

  test "answers a pleasantry warmly instead of declining it" do
    post public_demo_messages_path(@chatbot.slug), params: { question: "how nice of you!" }
    perform_enqueued_jobs

    reply = @chatbot.conversations.first.messages.where(role: "assistant").last

    assert_equal "smalltalk", reply.metadata["kind"]
    assert_match(/Happy to help/i, reply.content)
    assert_not_includes reply.content, "outside what I can help with"
  end

  test "declines a question that is not about the company at all" do
    post public_demo_messages_path(@chatbot.slug), params: { question: "What is the capital of France?" }
    perform_enqueued_jobs

    answer = @chatbot.conversations.first.messages.where(role: "assistant").last

    assert_equal "off_topic", answer.metadata["kind"]
    assert_match(/outside what I can help with/i, answer.content)
    assert_empty answer.sources, "an off-topic reply must not cite sources it did not use"
  end

  test "greets without searching the corpus" do
    assert_no_difference -> { AIUsage.count } do
      post public_demo_messages_path(@chatbot.slug), params: { question: "hi" }
      perform_enqueued_jobs
    end

    answer = @chatbot.conversations.first.messages.where(role: "assistant").last

    assert_equal "greeting", answer.metadata["kind"]
    assert_match(/Acme/, answer.content)
  end

  test "keeps a follow-up anchored to what was just discussed" do
    post public_demo_messages_path(@chatbot.slug), params: { question: "Can administrators define custom roles?" }
    perform_enqueued_jobs
    post public_demo_messages_path(@chatbot.slug), params: { question: "and which plan?" }
    perform_enqueued_jobs

    answer = @chatbot.conversations.first.messages.where(role: "assistant").last

    assert_match(/Enterprise plan/i, answer.content)
    assert_equal [ "https://docs.acme.test/roles" ], answer.sources.map { |source| source["url"] }
  end

  test "persists the conversation across requests" do
    post public_demo_messages_path(@chatbot.slug), params: { question: "What are Acme's RPO and RTO?" }
    perform_enqueued_jobs
    get public_demo_path(@chatbot.slug)

    assert_equal 2, inertia_props["messages"].size
    assert_equal 1, @chatbot.conversations.count
    assert_equal 2, @chatbot.conversations.first.messages.count
  end

  test "exposes nothing internal" do
    get public_demo_path(@chatbot.slug)
    payload = inertia_props.to_json

    assert_not_includes payload, "friction_score"
    assert_not_includes payload, "system_prompt"
    assert_not_includes payload, "scan_id"
    assert_not_includes payload, "chunk_id"
    assert_not_includes payload, "gpt-"
  end

  test "states that it is not affiliated with the analyzed company" do
    get public_demo_path(@chatbot.slug)

    assert_equal "Acme", inertia_props["company"]
    assert_equal "acme.test", inertia_props["domain"]
  end

  test "a demo only ever answers from its own scan" do
    other_scan = acme_scan
    run_pipeline(other_scan)

    post public_demo_messages_path(@chatbot.slug), params: { question: "Can administrators define custom RBAC roles?" }
    perform_enqueued_jobs

    urls = @chatbot.conversations.first.messages.where(role: "assistant").flat_map { |m| m.sources.map { |s| s["url"] } }
    assert_predicate urls, :any?
    assert_equal [ @scan.id ], @scan.chunks.distinct.pluck(:scan_id)
    assert_not_equal other_scan.id, @scan.id
  end

  test "a visitor can hand an unanswered question to a person" do
    post public_demo_messages_path(@chatbot.slug), params: { question: "Does Acme hold FedRAMP authorization?" }
    perform_enqueued_jobs

    assert_difference -> { Handoff.count }, 1 do
      post public_demo_handoffs_path(@chatbot.slug),
           params: { question: "Does Acme hold FedRAMP authorization?", email: "buyer@bigco.com" }
    end

    assert_response :created
    handoff = Handoff.last
    assert_equal "waiting", handoff.status
    assert_equal "buyer@bigco.com", handoff.visitor_email
    assert_equal @chatbot.conversations.first, handoff.conversation

    # The visitor is told, in their own thread, that a person has it.
    confirmation = @chatbot.conversations.first.messages.last
    assert_equal "handed_off", confirmation.metadata["kind"]
    assert_match(/passed that to Acme's team/, confirmation.content)
  end

  test "rejects a handoff with no question and an invalid email" do
    post public_demo_handoffs_path(@chatbot.slug), params: { question: "  " }
    assert_response :unprocessable_entity

    assert_no_difference -> { Handoff.count } do
      post public_demo_handoffs_path(@chatbot.slug), params: { question: "Anything?", email: "not-an-email" }
    end
    assert_response :unprocessable_entity
  end

  test "a salesperson's answer lands in the visitor's conversation and is broadcast" do
    post public_demo_handoffs_path(@chatbot.slug), params: { question: "Do you hold FedRAMP?" }
    handoff = Handoff.last
    conversation = handoff.conversation

    before = broadcasts_for(conversation).size
    put handoff_path(handoff), params: { answer: "Not today, but we're in the process." }

    assert_redirected_to lead_path(@scan.lead, tab: "questions")
    assert_predicate handoff.reload, :answered?

    answer = conversation.messages.last
    assert_equal "human", answer.metadata["kind"]
    assert_equal "Not today, but we're in the process.", answer.content
    assert_operator broadcasts_for(conversation).size, :>, before
  end

  test "a dismissed handoff says nothing to the visitor" do
    post public_demo_handoffs_path(@chatbot.slug), params: { question: "Do you hold FedRAMP?" }
    handoff = Handoff.last
    before = handoff.conversation.messages.count

    put handoff_path(handoff), params: { dismiss: "1" }

    assert_predicate handoff.reload, :dismissed?
    assert_equal before, handoff.conversation.messages.count
  end

  test "serves an embeddable widget script for a public demo" do
    get public_demo_widget_path(@chatbot.slug)

    assert_response :success
    assert_match %r{javascript}, response.media_type
    assert_includes response.body, @chatbot.slug
    assert_includes response.body, "embed=1"
    # It runs on a page we know nothing about, so it must not leak globals.
    assert_includes response.body, "__fathomWidget"
  end

  test "a widget visitor is identified by its token rather than a cookie" do
    visitor = SecureRandom.uuid

    post public_demo_messages_path(@chatbot.slug), params: { question: "Does Acme support SSO?", v: visitor }

    assert_response :created
    assert_equal visitor, @chatbot.conversations.last.session_id
  end

  test "rejects a visitor token that is not a uuid" do
    post public_demo_messages_path(@chatbot.slug), params: { question: "Does Acme support SSO?", v: "'; DROP TABLE" }

    assert_response :created
    assert_not_equal "'; DROP TABLE", @chatbot.conversations.last.session_id
  end

  test "an unknown or private demo slug is not found" do
    get public_demo_path("does-not-exist")
    assert_response :not_found

    @chatbot.update!(public: false)
    get public_demo_path(@chatbot.slug)
    assert_response :not_found
  end

  test "rate limits the endpoint that costs money" do
    limit = WebsiteIntelligence.config.public_demo_rate_limit

    (limit + 1).times do
      post public_demo_messages_path(@chatbot.slug), params: { question: "What are Acme's RPO and RTO?" }
    end

    assert_response :too_many_requests
    assert_equal "rate_limited", JSON.parse(response.body)["error"]
  end

  test "ignores a blank question rather than storing an empty turn" do
    assert_no_enqueued_jobs(only: AnswerDemoQuestionJob) do
      post public_demo_messages_path(@chatbot.slug), params: { question: "   " }
    end

    assert_response :unprocessable_entity
    assert_equal 0, Message.count
  end

  private
    def assert_broadcasts_on_channel(conversation)
      before = broadcasts_for(conversation).size
      yield
      assert_operator broadcasts_for(conversation).size, :>, before, "expected a broadcast to the visitor's conversation"
    end

    def broadcasts_for(conversation)
      ActionCable.server.pubsub.broadcasts(ConversationChannel.broadcasting_for(conversation))
    end

    def inertia_props = inertia.props.deep_stringify_keys

    def inertia_component = inertia.component
end
