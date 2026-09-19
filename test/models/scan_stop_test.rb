require "test_helper"

class ScanStopTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup { @scan = acme_scan }

  test "a stopped scan is finished, so the pipeline will not advance it" do
    @scan.claim_stage(:crawling)

    assert @scan.stop!
    assert_predicate @scan, :stopped?
    assert_predicate @scan, :finished?
    assert_not @scan.running?
  end

  test "stopping keeps what the scan already found" do
    scan = indexed_acme_scan
    pages = scan.pages.count
    chunks = scan.chunks.count

    scan.stop!

    assert_equal pages, scan.pages.count
    assert_equal chunks, scan.chunks.count
    assert_operator pages, :>, 0
  end

  test "the pipeline refuses to move a stopped scan on" do
    @scan.claim_stage(:crawling)
    @scan.stop!

    assert_no_enqueued_jobs { @scan.pipeline.advance! }
  end

  test "a stage that was already on a worker does nothing when it wakes" do
    scan = indexed_acme_scan
    scan.stop!

    assert_no_difference -> { scan.claims.count } do
      ExtractClaimsJob.perform_now(scan)
    end
  end

  test "stopping twice is not an error, and says so" do
    assert @scan.stop!
    assert_not @scan.stop!
  end

  test "a finished scan cannot be stopped out of its own state" do
    @scan.complete!

    assert_not @scan.stop!
    assert_predicate @scan.reload, :completed?
  end

  test "stopping frees the slot for whoever is queued behind it" do
    @scan.claim_stage(:crawling)
    waiting = Scan.start!(Lead.for_website("https://other.test"))

    assert_enqueued_with(job: StartScanJob) { @scan.stop! }
    assert_predicate waiting.reload, :pending?
  end

  test "a stopped scan resumes from where it stopped" do
    @scan.claim_stage(:crawling)
    @scan.stop!

    assert @scan.resume!
    assert_predicate @scan.reload, :pending?
  end

  test "a stopped scan is not counted as live" do
    @scan.claim_stage(:crawling)
    @scan.stop!

    assert_empty Scan::Admission.live_scans
  end

  test "stopping tells the pages that are watching" do
    @scan.claim_stage(:crawling)

    assert_broadcasts(ScanChannel::LIST_STREAM, 1) { @scan.stop! }
  end

  test "deleting a scan takes its evidence and leaves its cost" do
    scan = indexed_acme_scan
    AIUsage.record(operation: "embedding", provider: "openai", model: "text-embedding-3-small",
                   scan: scan, estimated_cost: 0.02)

    assert_difference -> { Page.count }, -scan.pages.count do
      scan.destroy
    end

    assert_equal 1, AIUsage.where(scan_id: nil).where(estimated_cost: 0.02).count,
                 "what a scan cost is still true after the scan is gone"
  end
end
