require "test_helper"

class CrawlPlanTest < ActiveSupport::TestCase
  setup do
    @scan = acme_scan
    Website::Map.new(@scan).discover!
    ClassifyUrlsJob.perform_now(@scan)
  end

  test "selects a subset rather than everything discovered" do
    CrawlPlan.new(@scan).select!

    assert_operator @scan.discovered_urls.selected.count, :<, @scan.discovered_urls.count
    assert_equal @scan.discovered_urls.selected.count, @scan.reload.pages_selected
  end

  test "always includes a representative buyer-visible corpus" do
    CrawlPlan.new(@scan).select!
    selected = @scan.discovered_urls.selected

    assert selected.where(corpus_type: CorpusTypes::BUYER_VISIBLE).exists?
    assert selected.where(corpus_type: CorpusTypes::DEEP).exists?
    assert selected.exists?(page_type: "homepage")
    assert selected.exists?(page_type: "pricing")
  end

  test "prioritises deep technical content" do
    CrawlPlan.new(@scan).select!
    selected = @scan.discovered_urls.selected

    assert_operator selected.where(corpus_type: CorpusTypes::DEEP).count,
                    :>,
                    selected.where(corpus_type: CorpusTypes::BUYER_VISIBLE).count
  end

  test "never selects low-value or redundant URLs" do
    CrawlPlan.new(@scan).select!
    selected = @scan.discovered_urls.selected

    assert_not selected.exists?(page_type: "blog")
    assert_not selected.exists?(page_type: "careers")
    assert_not selected.exists?(canonical_url: "https://acme.test/de/pricing")
  end

  test "honours the page budget and still reserves room for buyer-visible pages" do
    CrawlPlan.new(@scan, budget: 8).select!
    selected = @scan.discovered_urls.selected

    assert_equal 8, selected.count
    assert_operator selected.where(corpus_type: CorpusTypes::BUYER_VISIBLE).count, :>=, 1
  end

  test "records a summary that explains the plan" do
    summary = CrawlPlan.new(@scan).select!.summary

    assert_equal @scan.discovered_urls.count, summary[:discovered]
    assert_operator summary[:high_priority], :>, 0
    assert_operator summary[:skipped_redundant_variants], :>, 0
    assert_equal @scan.discovered_urls.selected.count, summary[:selected]
    assert @scan.reload.plan_summary.present?
  end

  test "is idempotent" do
    CrawlPlan.new(@scan).select!
    first = @scan.discovered_urls.selected.pluck(:id).sort

    CrawlPlan.new(@scan).select!

    assert_equal first, @scan.discovered_urls.selected.pluck(:id).sort
  end
end
