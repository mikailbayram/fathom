require "test_helper"

class AI::AnswererTest < ActiveSupport::TestCase
  RBAC = "Can administrators define custom RBAC roles in Acme rather than using only predefined roles?"

  setup do
    @scan = indexed_acme_scan
    @answerer = AI::Answerer.build(@scan)
  end

  test "fake mode never builds a live answerer, even with a key in the environment" do
    with_env("OPENAI_API_KEY" => "sk-should-be-ignored") do
      assert_instance_of AI::Answerer::Fake, AI::Answerer.build(@scan)
    end
  end

  test "answers a question the deep corpus establishes" do
    answer = @answerer.answer(RBAC)

    assert_predicate answer, :answerable?
    assert_operator answer.coverage, :>=, WebsiteIntelligence.config.minimum_answer_confidence
    assert_match(/custom RBAC roles/i, answer.text)
    assert_match(/Enterprise plan/i, answer.text)
  end

  test "attaches the sources it actually used" do
    answer = @answerer.answer(RBAC)

    assert_predicate answer.chunk_ids, :any?
    assert_includes @scan.chunks.where(id: answer.chunk_ids).map(&:source_url), "https://docs.acme.test/roles"
    assert_equal answer.chunk_ids.size, answer.source_attributes.size
    assert_equal 1, answer.source_attributes.count { |attributes| attributes[:is_primary] }
  end

  test "quotes only prose, never the retrieval context line" do
    assert_not_includes @answerer.answer(RBAC).text, " -- "
  end

  test "cannot answer the same question from the buyer-visible corpus" do
    answer = @answerer.answer(RBAC, scope: :buyer_visible)

    assert_not answer.answerable?
    assert_operator answer.coverage, :<, 0.5
    assert answer.reasoning.present?, "an unanswerable result should explain itself"
  end

  test "refuses a question the corpus does not address" do
    answer = @answerer.answer("Does Acme hold FedRAMP authorization?")

    assert_not answer.answerable?
    assert_nil answer.text
    assert_empty answer.chunk_ids
  end

  test "will not answer about one named system using another's documentation" do
    answer = @answerer.answer("Does Acme's Snowflake integration support bidirectional synchronization?")
    sources = @scan.chunks.where(id: answer.chunk_ids).map(&:source_url)

    assert_not_includes sources, "https://developers.acme.test/netsuite",
                        "a Snowflake question must not be answered from the NetSuite page"
    assert_not answer.answerable?, "nothing in the corpus documents a Snowflake sync direction"
  end

  test "answers the NetSuite question from the NetSuite page" do
    answer = @answerer.answer("Does Acme's NetSuite integration support bidirectional synchronization?")

    assert_predicate answer, :answerable?
    assert_includes @scan.chunks.where(id: answer.chunk_ids).map(&:source_url), "https://developers.acme.test/netsuite"
    assert_match(/one-way/i, answer.text)
  end

  test "answers a prominently published question from the buyer-visible corpus too" do
    question = "Which Acme plan includes SAML single sign-on?"

    assert_predicate @answerer.answer(question), :answerable?
    assert_predicate @answerer.answer(question, scope: :buyer_visible), :answerable?
  end

  test "is deterministic" do
    first = @answerer.answer(RBAC)
    second = AI::Answerer.build(@scan).answer(RBAC)

    assert_equal first.text, second.text
    assert_equal first.coverage, second.coverage
    assert_equal first.chunk_ids, second.chunk_ids
  end

  test "returns an unanswerable result when nothing is indexed at all" do
    answer = AI::Answerer.build(acme_scan).answer(RBAC)

    assert_not answer.answerable?
    assert_equal 0.0, answer.coverage
  end

  test "a claim the corpus is silent on has zero coverage, not high certainty" do
    # The field used to be called confidence, and a model asked for confidence
    # answers with certainty in its own verdict: "I am 99% sure this is not
    # stated" came back as 0.99 and scored as prominently available. Every
    # buried fact was penalised for being easy to find, and across three real
    # scans not one of 255 findings cleared the threshold.
    answer = AI::Answerer.build(indexed_acme_scan)
                         .answer("What is the maximum supported reactor vessel pressure?", scope: :buyer_visible)

    assert_not_predicate answer, :answerable?
    assert_operator answer.coverage, :<, 0.5,
                    "coverage measures the corpus, so silence must read as low"
  end

  test "coverage rises with how completely the sources state the claim" do
    scan = indexed_acme_scan
    answerer = AI::Answerer.build(scan)

    stated = answerer.answer("Can administrators define custom roles and permissions?", scope: :all)
    silent = answerer.answer("What is the maximum supported reactor vessel pressure?", scope: :all)

    assert_operator stated.coverage, :>, silent.coverage
  end
end
