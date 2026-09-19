require "test_helper"

class Corpus::SearchTest < ActiveSupport::TestCase
  setup do
    @scan = indexed_acme_scan
    @search = Corpus::Search.new(@scan)
  end

  test "retrieves the deep documentation that answers a technical question" do
    results = @search.find("custom RBAC roles")

    assert_predicate results, :any?
    assert_includes results.map(&:source_url), "https://docs.acme.test/roles"
  end

  test "scopes retrieval to the buyer-visible corpus" do
    results = @search.find("custom RBAC roles", scope: :buyer_visible)

    assert_equal [ CorpusTypes::BUYER_VISIBLE ], results.map(&:corpus_type).uniq
    assert_not_includes results.map(&:source_url), "https://docs.acme.test/roles"
  end

  test "scopes retrieval to the deep corpus" do
    results = @search.find("pricing plans", scope: :deep)

    assert_equal [ CorpusTypes::DEEP ], results.map(&:corpus_type).uniq
  end

  test "searches both corpora by default" do
    corpora = @search.find("Acme plan", limit: 30).map(&:corpus_type).uniq

    assert_includes corpora, CorpusTypes::DEEP
    assert_includes corpora, CorpusTypes::BUYER_VISIBLE
  end

  test "rejects an unknown scope rather than silently searching everything" do
    assert_raises(Corpus::Search::UnknownScope) { @search.find("anything", scope: :everything) }
  end

  test "returns nothing for a blank query" do
    assert_empty @search.find("")
    assert_empty @search.find(nil)
  end

  test "finds exact enterprise terminology through lexical search" do
    results = @search.find("RPO RTO")

    assert_includes results.map(&:source_url), "https://acme.test/enterprise-guide.pdf"
    assert results.any?(&:lexical?), "the lexical half should have contributed candidates"
  end

  test "finds paraphrased questions through vector similarity" do
    results = @search.find("what happens if a delivery to our endpoint is rejected")

    assert results.any?(&:semantic?), "the semantic half should have contributed candidates"
  end

  test "ranks a chunk found by both methods above one found by either" do
    results = @search.find("custom RBAC roles granular resource permissions")
    both = results.select(&:both?)

    assert_predicate both, :any?
    assert_equal results.first.id, both.first.id
  end

  test "deduplicates chunks found by both methods" do
    ids = @search.find("custom RBAC roles", limit: 30).map(&:id)

    assert_equal ids.uniq.size, ids.size
  end

  test "honours the result limit" do
    assert_operator @search.find("Acme", limit: 3).size, :<=, 3
  end

  test "never returns chunks from another scan" do
    other = indexed_acme_scan

    assert_equal [ @scan.id ], @search.find("custom roles", limit: 30).map { |c| c.chunk.scan_id }.uniq
    assert_not_equal other.id, @scan.id
  end
end
