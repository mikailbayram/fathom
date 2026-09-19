# frozen_string_literal: true

# Hard limits on what one scan, and one day, may cost.
#
# In fake mode both budgets are zero, which is not a formality: it means a code
# path that accidentally reaches a paid provider fails loudly in development and
# CI rather than quietly billing someone.
class SpendingLimit
  class Exceeded < StandardError; end

  def initialize(scan: nil)
    @scan = scan
  end

  # A handful of calls may legitimately come back without usage metadata, but a
  # steady stream of them means the price is not reaching us at all -- a model
  # the provider does not price, or an aggregator that was never asked to report
  # what it charges. Spending is then unbounded, so it stops here instead.
  UNPRICED_TOLERANCE = 5

  def enforce!
    raise Exceeded, scan_message if scan && scan_exhausted?
    raise Exceeded, unpriced_message if scan && flying_blind?
    raise Exceeded, daily_message if daily_exhausted?

    true
  end

  def exceeded? = (scan && scan_exhausted?) || daily_exhausted?

  def scan_spend = @scan ? @scan.estimated_cost_usd.to_f : 0.0

  def scan_budget = WebsiteIntelligence.max_scan_ai_cost_usd

  def daily_spend = AIUsage.today.sum(:estimated_cost).to_f

  def daily_budget = WebsiteIntelligence.max_daily_ai_cost_usd

  # A rough workload estimate shown before an unusually large live scan, so a
  # five thousand page crawl is never started by accident.
  def self.estimate(pages:)
    chunks = pages * 6
    passages = [ chunks, WebsiteIntelligence.config.max_claim_passages ].min

    {
      pages: pages,
      estimated_chunks: chunks,
      estimated_embedding_tokens: chunks * WebsiteIntelligence.config.chunk_target_tokens,
      # Extraction reads a bounded set of passages, and each claim it finds
      # costs one buyer-visible check.
      estimated_extraction_passages: passages,
      estimated_claims: [ passages / 3, WebsiteIntelligence.config.max_claims_per_scan ].min,
      budget_usd: WebsiteIntelligence.max_scan_ai_cost_usd
    }
  end

  private
    attr_reader :scan

    def scan_exhausted? = scan_spend >= scan_budget

    def unpriced_calls = @scan ? @scan.ai_usages.unpriced.count : 0

    def flying_blind? = unpriced_calls > UNPRICED_TOLERANCE

    def daily_exhausted? = daily_spend >= daily_budget

    # Named as this application's own limit, because it is not a provider
    # billing failure and reads exactly like one when it is not said out loud.
    def scan_message
      format(
        "Scan #%d reached the per-scan AI budget set in MAX_SCAN_AI_COST_USD: $%.2f spent of $%.2f allowed. " \
        "The provider was not contacted, and nothing is wrong with the account.",
        scan.id, scan_spend, scan_budget
      )
    end

    def daily_message
      format(
        "Today's AI spend reached the daily limit set in MAX_DAILY_AI_COST_USD: $%.2f of $%.2f allowed. " \
        "The provider was not contacted, and nothing is wrong with the account.",
        daily_spend, daily_budget
      )
    end

    def unpriced_message
      format(
        "Scan #%d has %d AI calls the provider reported no cost for, so its $%.2f budget cannot be enforced. " \
        "Check that the configured provider reports usage costs before scanning further.",
        scan.id, unpriced_calls, scan_budget
      )
    end
end
