require "test_helper"

class Scan::PipelineTest < ActiveSupport::TestCase
  setup { @scan = acme_scan }

  test "starts at mapping" do
    assert_equal "mapping", @scan.pipeline.next_step.stage
  end

  test "advances stage by stage as the database changes" do
    assert_equal "mapping", @scan.pipeline.next_step.stage

    Website::Map.new(@scan).discover!
    assert_equal "classifying", @scan.pipeline.next_step.stage

    ClassifyUrlsJob.perform_now(@scan)
    assert_equal "planning", @scan.pipeline.next_step.stage

    CrawlPlan.new(@scan).select!
    assert_equal "crawling", @scan.pipeline.next_step.stage
  end

  test "enqueues the job for the next stage and records the stage on the scan" do
    assert_enqueued_with(job: MapWebsiteJob) { @scan.pipeline.advance! }
    assert_equal "mapping", @scan.reload.status
  end

  test "finalizes once every stage is behind it" do
    run_pipeline(@scan)

    assert_predicate @scan.pipeline, :complete?
    assert_predicate @scan, :completed?
  end

  test "never advances a failed scan" do
    @scan.fail!(stage: "mapping", error: "boom")

    assert_no_enqueued_jobs { @scan.pipeline.advance! }
  end

  test "reports no stage as complete before the pipeline has reached it" do
    Website::Map.new(@scan).discover!
    ClassifyUrlsJob.perform_now(@scan)
    CrawlPlan.new(@scan).select!
    progress = @scan.pipeline.progress

    assert_equal %w[complete complete complete], progress.first(3).map { |step| step[:state] }
    assert_equal "active", progress[3][:state]
    assert_equal %w[pending], progress.drop(4).map { |step| step[:state] }.uniq
  end

  test "labels the failed stage rather than leaving the UI to guess" do
    Website::Map.new(@scan).discover!
    @scan.fail!(stage: "planning", error: "Crawler::Client::Error: upstream refused")
    progress = @scan.pipeline.progress

    assert_equal "failed", progress.find { |step| step[:stage] == "planning" }[:state]
    assert_equal "planning", @scan.failed_stage
    assert_match(/upstream refused/, @scan.error_message)
  end

  test "describes what each completed stage produced" do
    Website::Map.new(@scan).discover!
    detail = @scan.pipeline.progress.first[:detail]

    assert_match(/\A\d+ URLs discovered\z/, detail)
  end

  test "is rerunnable from a completed state" do
    run_pipeline(@scan)
    findings = @scan.findings.viable.count

    @scan.update!(status: "pending")
    run_pipeline(@scan)

    assert_predicate @scan.reload, :completed?
    assert_equal findings, @scan.findings.viable.count
  end

  test "only one caller can claim a stage" do
    # A hundred and twenty claim checks finish across eight threads, each asks
    # the pipeline what is next, and each sees the last claim resolved. Reading
    # the status and then writing it let all of them start the coverage audit:
    # five ran at once, regenerating the checklist ten times over.
    scan = acme_scan
    scan.claim_stage(:scoring)

    winners = 8.times
      .map { Thread.new { Rails.application.executor.wrap { Scan.find(scan.id).claim_stage(:auditing_coverage) } } }
      .map(&:value)

    assert_equal 1, winners.count(true), "exactly one caller advances the stage"
    assert_equal "auditing_coverage", scan.reload.status
  end

  test "a stage already running is not claimed again" do
    scan = acme_scan

    assert scan.claim_stage(:crawling)
    assert_not scan.claim_stage(:crawling)
  end

  test "a long-running stage cannot be reclaimed because time passed" do
    scan = acme_scan
    scan.claim_stage(:crawling)
    scan.update_columns(updated_at: 2.hours.ago)

    assert_not scan.reload.claim_stage(:crawling)
  end

  test "a late caller refreshes its facts before advancing" do
    stale_pipeline = @scan.pipeline
    assert_equal "mapping", stale_pipeline.next_step.stage

    Website::Map.new(@scan).discover!
    @scan.pipeline.advance!

    assert_no_enqueued_jobs { stale_pipeline.advance! }
    assert_equal "classifying", @scan.reload.status
  end

  test "an enqueue failure does not leave the stage claimed without work" do
    with_stub(MapWebsiteJob, :perform_later, ->(*) { raise "queue unavailable" }) do
      assert_raises(RuntimeError) { @scan.pipeline.advance! }
    end

    assert_predicate @scan.reload, :pending?
    assert_enqueued_with(job: MapWebsiteJob) { @scan.pipeline.advance! }
  end

  test "advancing twice at once enqueues the next stage only once" do
    scan = acme_scan

    assert_enqueued_jobs 1 do
      2.times { Scan.find(scan.id).pipeline.advance! }
    end
  end

  test "finalizing twice completes the scan once" do
    # Nothing claims a stage for finalizing, so the job refuses to run again on
    # a scan that is already finished -- otherwise each run would free the
    # admission slot and let two queued scans start together.
    scan = acme_scan
    stale_scan = Scan.find(scan.id)
    FinalizeScanJob.perform_now(scan)
    completed_at = scan.reload.completed_at

    travel 1.minute do
      assert_no_enqueued_jobs(only: StartScanJob) { FinalizeScanJob.perform_now(stale_scan) }
      assert_equal completed_at, scan.reload.completed_at
    end
  end
end
