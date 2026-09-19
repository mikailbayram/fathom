require "test_helper"

class SpendingLimitTest < ActiveSupport::TestCase
  setup { @scan = acme_scan }

  test "fake mode budgets nothing, so any real spend is a failure" do
    assert_equal 0.0, SpendingLimit.new(scan: @scan).scan_budget

    AIUsage.record(operation: "company_analysis", provider: "openai", model: "gpt-5.6-terra",
                   scan: @scan, estimated_cost: 0.01)

    assert_raises(SpendingLimit::Exceeded) { SpendingLimit.new(scan: @scan).enforce! }
  end

  test "allows spending under the scan budget" do
    WebsiteIntelligence.config.max_scan_ai_cost_usd = 2.0
    WebsiteIntelligence.config.max_daily_ai_cost_usd = 10.0
    WebsiteIntelligence.stub_mode(:live) do
      AIUsage.record(operation: "embedding", provider: "openai", model: "x", scan: @scan, estimated_cost: 0.5)

      assert SpendingLimit.new(scan: @scan).enforce!
    end
  end

  test "stops a scan that has spent its budget" do
    WebsiteIntelligence.config.max_scan_ai_cost_usd = 1.0
    WebsiteIntelligence.config.max_daily_ai_cost_usd = 100.0
    WebsiteIntelligence.stub_mode(:live) do
      AIUsage.record(operation: "embedding", provider: "openai", model: "x", scan: @scan, estimated_cost: 1.5)

      error = assert_raises(SpendingLimit::Exceeded) { SpendingLimit.new(scan: @scan).enforce! }
      assert_match(/MAX_SCAN_AI_COST_USD/, error.message)
      assert_match(/nothing is wrong with the account/, error.message,
                   "an operator must not read this as a provider billing failure")
    end
  end

  test "stops everything once the daily budget is gone" do
    WebsiteIntelligence.config.max_scan_ai_cost_usd = 100.0
    WebsiteIntelligence.config.max_daily_ai_cost_usd = 1.0
    WebsiteIntelligence.stub_mode(:live) do
      AIUsage.record(operation: "embedding", provider: "openai", model: "x", estimated_cost: 2.0)

      error = assert_raises(SpendingLimit::Exceeded) { SpendingLimit.new.enforce! }
      assert_match(/MAX_DAILY_AI_COST_USD/, error.message)
    end
  end

  test "refuses to keep spending when the provider reports no cost" do
    # An aggregator that is not asked for usage accounting returns no price at
    # all. Summed as zero, the budget silently stops existing.
    WebsiteIntelligence.config.max_scan_ai_cost_usd = 2.0
    WebsiteIntelligence.config.max_daily_ai_cost_usd = 100.0
    WebsiteIntelligence.stub_mode(:live) do
      (SpendingLimit::UNPRICED_TOLERANCE + 1).times do
        AIUsage.record(operation: "claim_extraction", provider: "openrouter", model: "x", scan: @scan)
      end

      error = assert_raises(SpendingLimit::Exceeded) { SpendingLimit.new(scan: @scan).enforce! }
      assert_match(/no cost for/, error.message)
    end
  end

  test "tolerates the occasional response that carries no usage metadata" do
    WebsiteIntelligence.config.max_scan_ai_cost_usd = 2.0
    WebsiteIntelligence.config.max_daily_ai_cost_usd = 100.0
    WebsiteIntelligence.stub_mode(:live) do
      AIUsage.record(operation: "claim_extraction", provider: "openrouter", model: "x", scan: @scan)

      assert SpendingLimit.new(scan: @scan).enforce!
    end
  end

  test "a fake-mode call costs nothing and is not mistaken for an unpriced one" do
    WebsiteIntelligence.config.max_scan_ai_cost_usd = 2.0
    WebsiteIntelligence.config.max_daily_ai_cost_usd = 100.0
    WebsiteIntelligence.stub_mode(:live) do
      10.times { AIUsage.record(operation: "embedding", provider: "fake", model: "x", scan: @scan) }

      assert SpendingLimit.new(scan: @scan).enforce!
    end
  end

  test "estimates a workload before an unusually large live scan" do
    estimate = SpendingLimit.estimate(pages: 1_000)

    assert_equal 1_000, estimate[:pages]
    assert_operator estimate[:estimated_chunks], :>, 1_000
    assert_operator estimate[:estimated_embedding_tokens], :>, 0
  end
end
