require "test_helper"

class Scan::WorkTest < ActiveSupport::TestCase
  setup do
    @scan = acme_scan
    @scan.claim_stage(:auditing_coverage)
    @scan.update_columns(updated_at: 2.hours.ago)
  end

  test "queued work remains live regardless of the scan timestamp" do
    SolidQueue::Job.enqueue(AuditCoverageJob.new(@scan))

    assert_not @scan.stalled?
    assert_no_enqueued_jobs { assert_not @scan.resume! }
    assert_equal "auditing_coverage", @scan.reload.status
  end

  test "a long-running claimed job prevents a second execution" do
    job = SolidQueue::Job.enqueue(AuditCoverageJob.new(@scan))
    job.ready_execution.destroy!
    process = SolidQueue::Process.register(kind: "Worker", name: SecureRandom.uuid, pid: Process.pid)
    SolidQueue::ClaimedExecution.create!(job: job, process: process)

    assert_not @scan.stalled?
    assert_no_enqueued_jobs { assert_not @scan.resume! }
    assert_not @scan.claim_stage(:auditing_coverage)
  end

  test "a scheduled retry is still unfinished work" do
    SolidQueue::Job.enqueue(AuditCoverageJob.new(@scan), scheduled_at: 10.minutes.from_now)

    assert_not @scan.stalled?
    assert_no_enqueued_jobs { assert_not @scan.resume! }
  end

  test "a failed queue execution can be resumed once" do
    job = SolidQueue::Job.enqueue(AuditCoverageJob.new(@scan))
    job.ready_execution.destroy!
    SolidQueue::FailedExecution.create!(job: job, error: { exception_class: "SolidQueue::Processes::ProcessExitError" })

    assert @scan.stalled?
    assert_enqueued_with(job: StartScanJob, args: [ @scan ]) { assert @scan.resume! }
    assert_no_enqueued_jobs { assert_not @scan.resume! }
    assert_predicate @scan.reload, :pending?
  end

  test "finished work does not prevent recovery of an unfinished scan" do
    job = SolidQueue::Job.enqueue(AuditCoverageJob.new(@scan))
    job.ready_execution.destroy!
    job.finished!

    assert @scan.stalled?
    assert_enqueued_with(job: StartScanJob) { assert @scan.resume! }
  end

  test "claim jobs belong to the scan as well" do
    claim = @scan.claims.create!(statement: "Supports SAML SSO", question_text: "Supports SAML?", category: "security_compliance", buyer_importance: 0.8)
    SolidQueue::Job.enqueue(CheckClaimVisibilityJob.new(claim))

    assert_not @scan.stalled?
    assert_no_enqueued_jobs { assert_not @scan.resume! }
    assert acme_other_scan.stalled?, "another scan's claim does not keep this scan alive"
  end

  test "a blocked crawl is queued work" do
    (CrawlPagesJob.concurrency_limit + 1).times { SolidQueue::Job.enqueue(CrawlPagesJob.new(@scan)) }

    assert @scan.work.blocked?
    assert_not @scan.stalled?
  end

  private
    def acme_other_scan
      Scan.start!(@scan.lead).tap { |scan| scan.claim_stage(:crawling) }
    end
end
