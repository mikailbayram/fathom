require "test_helper"

class AI::ExtractorTest < ActiveSupport::TestCase
  setup do
    @scan = indexed_acme_scan
    @extractor = AI::Extractor.build(@scan)
  end

  test "fake mode never builds a live extractor, even with a key in the environment" do
    with_env("OPENAI_API_KEY" => "sk-should-be-ignored") do
      assert_instance_of AI::Extractor::Fake, AI::Extractor.build(@scan)
    end
  end

  test "reads everything indexed, not only the documentation" do
    # Restricting extraction to the deep corpus meant a company without a docs
    # site produced nothing at all, however much it published elsewhere.
    assert_predicate @extractor.passages, :any?
    assert_equal CorpusTypes::RETRIEVABLE.sort, @extractor.passages.map(&:corpus_type).uniq.sort
  end

  test "selects passages that carry concrete information, whatever the industry" do
    # No SaaS vocabulary required: a number, a unit, a standard or an explicit
    # limit is what makes a passage worth reading, in any sector.
    @extractor.passages.each do |chunk|
      assert_operator chunk.body.length, :>=, 80
    end

    assert @extractor.passages.any? { |chunk| chunk.body.match?(/\d/) }
  end

  test "reads a manufacturer's passages, which name no SaaS concern at all" do
    scan = @scan
    page = scan.pages.first
    chunk = page.chunks.create!(
      scan: scan, corpus_type: CorpusTypes::DEEP, position: 999,
      content: "Build volume is 400 x 400 x 400 mm with a layer thickness of 30 um. " \
               "Certified to ISO 9001 and AS9100. Minimum order is 25 units with a lead time of 6 weeks.",
      metadata: { "url" => page.url, "page_type" => "pdf", "corpus_type" => CorpusTypes::DEEP }
    )
    chunk.update!(embedding: AI::Embedder.build.embed_one(chunk.content), embedded_at: Time.current)

    assert_includes AI::Extractor.build(scan.reload).passages.map(&:id), chunk.id
  end

  test "honours the passage budget so a large documentation site stays bounded" do
    WebsiteIntelligence.config.max_claim_passages = 3

    assert_equal 3, AI::Extractor.build(@scan).passages.size
  ensure
    WebsiteIntelligence.reset_configuration!
  end

  test "extracts what the company actually published rather than a fixed list" do
    statements = @extractor.claims.map(&:statement)

    assert_operator @extractor.claims.size, :>, 5
    assert statements.any? { |s| s.match?(/custom RBAC roles/i) }, "the signature claim"
    assert statements.any? { |s| s.match?(/six times using exponential backoff/i) }, "webhook retry behaviour"
    assert statements.any? { |s| s.match?(/EU data residency .* Enterprise plan/i) }, "a plan-gated capability"
    assert statements.any? { |s| s.match?(/NetSuite integration is one-way only/i) }, "an integration limit"
  end

  test "every claim cites the passage it came from" do
    @extractor.claims.each do |claim|
      assert claim.chunk_id.present?, "a claim with no source is not a claim"
      assert_equal @scan.id, Chunk.find(claim.chunk_id).scan_id
    end
  end

  test "every claim is supported by the passage it cites" do
    @extractor.claims.each do |claim|
      assert_operator claim.support, :>=, Claim::MINIMUM_SUPPORT, claim.statement
      # Every sentence of the statement comes from the passage, though not
      # necessarily contiguously: the extractor lifts the sentences that carry
      # the concern, which may be separated by others.
      body = Chunk.find(claim.chunk_id).body.downcase.squish
      claim.statement.downcase.squish.split(/(?<=[.!?])\s+/).each do |sentence|
        assert_includes body, sentence.strip
      end
    end
  end

  test "rejects headings and nav lists, which assert nothing" do
    statements = @extractor.claims.map(&:statement)

    assert_empty statements.select { |s| s.start_with?("-") }
    assert_empty statements.select { |s| s.match?(/\AReference material/) }
    assert statements.all? { |s| s.length >= 30 }
  end

  test "does not lift the same sentence twice under two topics" do
    openings = @extractor.claims.map { |c| [ c.chunk_id, c.statement.downcase.squish.first(90) ] }

    assert_equal openings.uniq.size, openings.size
  end

  test "derives a buyer question for every claim" do
    @extractor.claims.each do |claim|
      assert claim.question.present?
      assert_includes claim.question, "Acme"
      assert_includes Claim::CATEGORIES, claim.category
    end
  end

  test "does not report the same statement twice" do
    statements = @extractor.claims.map { |c| c.statement.downcase.squish }

    assert_equal statements.uniq.size, statements.size
  end

  test "caps the number of claims" do
    WebsiteIntelligence.config.max_claims_per_scan = 4

    assert_equal 4, AI::Extractor.build(@scan).claims.size
  ensure
    WebsiteIntelligence.reset_configuration!
  end

  test "is deterministic" do
    assert_equal @extractor.claims.map(&:statement), AI::Extractor.build(@scan).claims.map(&:statement)
  end

  test "finds nothing in a scan with no indexed corpus" do
    assert_empty AI::Extractor.build(acme_scan).claims
  end

  test "overlapping the batches does not change which claims come out, or their order" do
    # Extraction is one provider call per batch and a real site is dozens of
    # them, so they run concurrently. The result has to be the serial result:
    # deduplication and the per-scan cap both depend on the order.
    serial = with_extraction_concurrency(1) { AI::Extractor.build(@scan).claims }
    parallel = with_extraction_concurrency(6) { AI::Extractor.build(@scan).claims }

    assert_predicate serial, :any?, "the fixture has to produce claims for this to prove anything"
    assert_equal serial.map(&:statement), parallel.map(&:statement)
  end

  test "a batch that fails takes the stage down rather than silently losing its claims" do
    exploding = Class.new(AI::Extractor) do
      def extract(_batch) = raise("provider exploded")
      def batch_size = 1
    end

    error = assert_raises(RuntimeError) { with_extraction_concurrency(6) { exploding.new(@scan).claims } }

    assert_match(/provider exploded/, error.message)
  end

  private
    def with_extraction_concurrency(count)
      with_env("AI_CALL_CONCURRENCY" => count.to_s) do
        WebsiteIntelligence.reset_configuration!
        yield
      end
    ensure
      WebsiteIntelligence.reset_configuration!
    end
end
