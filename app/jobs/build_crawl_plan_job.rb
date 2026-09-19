# frozen_string_literal: true

# Stage two: choose which discovered URLs are worth fetching.
class BuildCrawlPlanJob < PipelineJob
  def stage = "planning"

  def perform(scan)
    ensure_mode!(scan)
    CrawlPlan.new(scan).select!
    advance(scan)
  end
end
