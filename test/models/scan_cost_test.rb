require "test_helper"

class ScanCostTest < ActiveSupport::TestCase
  setup { @scan = acme_scan }

  test "a fake scan costs nothing, which is the point of fake mode" do
    cost = ScanCost.new(@scan)

    assert_equal 0.0, cost.total
    assert_equal "$0.00", cost.label
    assert_predicate cost, :complete?
  end

  test "sums what the provider charged for the AI calls" do
    record_usage(0.012)
    record_usage(0.004)

    assert_in_delta 0.016, ScanCost.new(@scan).total, 0.0001
  end

  test "counts the crawler's metered requests on a live scan" do
    @scan.update!(mode: "live")
    3.times { |index| crawled_url(index) }

    requests = ScanCost::MAP_REQUESTS + 3
    expected = requests * WebsiteIntelligence.config.crawl_cost_per_request_usd

    assert_in_delta expected, ScanCost.new(@scan).crawl, 0.0001
  end

  test "a failed fetch was still a request the account paid for" do
    @scan.update!(mode: "live")
    crawled_url(0, error: "502 Bad Gateway")

    assert_operator ScanCost.new(@scan).crawl, :>, 0.0
  end

  test "charges nothing for a crawler that reads fixtures from disk" do
    3.times { |index| crawled_url(index) }

    assert_equal 0.0, ScanCost.new(@scan).crawl
  end

  test "marks the total as a floor while any call is unpriced" do
    record_usage(0.02)
    record_usage(nil, provider: "openai")
    cost = ScanCost.new(@scan)

    assert_equal 1, cost.unpriced_calls
    assert_not cost.complete?
    assert_equal "$0.02+", cost.label
  end

  test "a fake call without a price is not an unpriced call" do
    record_usage(nil)

    assert_predicate ScanCost.new(@scan), :complete?
  end

  test "reports one number for the page to show" do
    record_usage(0.5)
    payload = ScanCost.new(@scan).to_payload

    assert_equal %i[total label complete], payload.keys
    assert_equal "$0.50", payload[:label]
  end

  private
    def record_usage(cost, provider: "fake")
      AIUsage.record(operation: "answer_buyer_visible", provider: provider, model: "gpt-5.6-terra",
                     scan: @scan, estimated_cost: cost)
    end

    def crawled_url(index, error: nil)
      url = "https://acme.test/page-#{index}"
      @scan.discovered_urls.create!(
        url: url, canonical_url: url, host: "acme.test", path: "/page-#{index}", source: "sitemap",
        page_type: "docs", corpus_type: "deep", priority: 50, selected_for_crawl: true,
        crawled_at: Time.current, crawl_error: error
      )
    end
end
