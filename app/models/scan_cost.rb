# frozen_string_literal: true

# What one scan cost to run, in dollars: the AI calls plus the crawler.
#
#   cost = ScanCost.new(scan)
#   cost.total     # => 0.42
#   cost.label     # => "$0.42", or "$0.42+" when part of it is unknown
#
# The AI half is billed and recorded: AIUsage carries the provider's own figure
# per call. The crawler half is metered per request against an account rather
# than priced per response, so it is counted here and multiplied by the rate the
# operator configured. That makes it an estimate, and it is labelled as one.
#
# Fake and local mode cost nothing, which is the point of them.
class ScanCost
  # A crawler request is one API call: the map, and one fetch per page it was
  # asked for, whether or not that fetch came back with anything.
  MAP_REQUESTS = 1

  def initialize(scan)
    @scan = scan
  end

  # What the provider charged for the AI calls it priced.
  def ai = scan.ai_usages.sum(:estimated_cost).to_f

  def crawl = billable_crawler? ? crawler_requests * rate : 0.0

  def total = (ai + crawl).round(4)

  # Paid calls the provider never put a price on. The total is a floor, not a
  # figure, while any of these exist -- summing an unknown as zero is how a
  # number quietly stops meaning anything.
  def unpriced_calls = scan.ai_usages.unpriced.count

  def complete? = unpriced_calls.zero?

  def label = complete? ? formatted : "#{formatted}+"

  def to_payload = { total: total, label: label, complete: complete? }

  private
    attr_reader :scan

    def formatted = format("$%.2f", total)

    # Only the live crawler bills anyone. A fixture on disk does not.
    def billable_crawler? = scan.mode.to_s == "live"

    def crawler_requests = MAP_REQUESTS + scan.discovered_urls.where.not(crawled_at: nil).count

    def rate = WebsiteIntelligence.config.crawl_cost_per_request_usd
end
