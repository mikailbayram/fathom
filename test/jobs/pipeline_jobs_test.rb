require "test_helper"

class PipelineJobsTest < ActiveSupport::TestCase
  setup { @scan = acme_scan }

  # Stand-ins that fail the way a real provider outage would.
  def exploding_answerer
    Object.new.tap { |double| def double.answer(*) = raise("provider exploded") }
  end

  def exploding_crawler
    Object.new.tap do |double|
      def double.map(*) = raise(Crawler::Client::Error, "upstream refused")
      def double.fetch(*) = raise(Crawler::Client::Error, "upstream refused")
    end
  end

  test "a stage job is idempotent" do
    MapWebsiteJob.perform_now(@scan)
    first = @scan.reload.urls_discovered

    MapWebsiteJob.perform_now(@scan)

    assert_equal first, @scan.reload.urls_discovered
  end

  test "crawling continues itself until every selected page is fetched" do
    MapWebsiteJob.perform_now(@scan)
    BuildCrawlPlanJob.perform_now(@scan)

    perform_enqueued_jobs_until_idle(limit: 50) { CrawlPagesJob.perform_now(@scan) }

    assert_predicate Website::Crawl.new(@scan), :complete?
    assert_equal @scan.reload.pages.count, @scan.pages_crawled
  end

  test "a page that cannot be fetched is recorded and does not stall the crawl" do
    MapWebsiteJob.perform_now(@scan)
    BuildCrawlPlanJob.perform_now(@scan)

    broken = @scan.discovered_urls.selected.first
    broken.update!(url: "https://acme.test/does-not-exist", canonical_url: "https://acme.test/does-not-exist")

    perform_enqueued_jobs_until_idle(limit: 50) { CrawlPagesJob.perform_now(@scan) }

    assert broken.reload.crawled_at.present?, "the attempt is recorded even though it failed"
    assert broken.crawl_error.present?
    assert_predicate Website::Crawl.new(@scan), :complete?
  end

  test "one failing claim does not destroy the rest of the scan" do
    run_pipeline(@scan)
    viable = @scan.findings.viable.count
    claim = @scan.claims.first
    claim.update!(status: "pending")

    with_stub(AI::Answerer, :build, ->(*) { exploding_answerer }) do
      perform_enqueued_jobs_until_idle(limit: 30) { CheckClaimVisibilityJob.perform_later(claim) }
    end

    assert_equal "failed", claim.reload.status
    assert_match(/provider exploded/, claim.error_message)
    assert_equal viable, @scan.findings.viable.count, "the other answers survive"
    assert_not @scan.reload.failed?, "one bad question is not a failed scan"
  end

  test "a stage that keeps failing marks the scan failed and names the stage" do
    with_stub(Crawler::Client, :build, ->(*) { exploding_crawler }) do
      perform_enqueued_jobs_until_idle(limit: 30) { MapWebsiteJob.perform_later(@scan) }
    end

    assert_predicate @scan.reload, :failed?
    assert_equal "mapping", @scan.failed_stage
    assert_match(/upstream refused/, @scan.error_message)
    assert @scan.failed_at.present?
  end

  test "embedding processes chunks in batches until none are pending" do
    MapWebsiteJob.perform_now(@scan)
    BuildCrawlPlanJob.perform_now(@scan)
    perform_enqueued_jobs_until_idle(limit: 50) { CrawlPagesJob.perform_now(@scan) }
    perform_enqueued_jobs_until_idle(limit: 50) { ProcessPagesJob.perform_now(@scan) }
    perform_enqueued_jobs_until_idle(limit: 50) { EmbedChunksJob.perform_now(@scan) }

    assert_predicate Corpus::Index.new(@scan), :embedded?
    assert_equal 0, @scan.chunks.pending_embedding.count
    assert_operator @scan.reload.chunks_count, :>, 0
  end

  test "a chatbot is created for every completed scan" do
    run_pipeline(@scan)

    assert @scan.chatbot.present?
    assert_predicate @scan.chatbot, :publicly_shared?
    assert_match(/\Aacme-[0-9a-f]{6}\z/, @scan.chatbot.slug)
  end

  test "a failed scan can be retried from where it stopped" do
    MapWebsiteJob.perform_now(@scan)
    @scan.fail!(stage: "planning", error: "boom")

    @scan.update!(status: "pending", failed_at: nil, failed_stage: nil, error_message: nil)
    run_pipeline(@scan)

    assert_predicate @scan.reload, :completed?
  end

  test "chatbot creation costs nothing and grounds its own persona" do
    run_pipeline(@scan)
    prompt = @scan.chatbot.system_prompt

    assert prompt.present?, "the persona the responder sends has to exist"
    assert_includes prompt, "Acme"
    assert_includes prompt, "NetSuite", "known integrations belong in the persona"
    assert_equal [ "fake" ], AIUsage.where(scan: @scan).distinct.pluck(:provider)
  end

  test "finalizing settles the counters the UI reads" do
    run_pipeline(@scan)

    assert_equal @scan.discovered_urls.count, @scan.urls_discovered
    assert_equal @scan.pages.count, @scan.pages_crawled
    assert_equal @scan.chunks.count, @scan.chunks_count
    assert_equal @scan.claims.count, @scan.claims_count
    assert_equal @scan.findings.viable.count, @scan.findings_count
    assert @scan.completed_at.present?
  end
end
