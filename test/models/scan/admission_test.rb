require "test_helper"

class Scan::AdmissionTest < ActiveSupport::TestCase
  setup do
    @first = acme_scan
    @second = Scan.start!(Lead.for_website("https://other.test"))
  end

  test "a scan may start when nothing else is running" do
    assert_predicate Scan::Admission.new(@first), :admit?
  end

  test "a second scan waits while the first is live" do
    # One crawler account and one provider account, both metered per minute:
    # two scans at once spend their time being refused, not working.
    @first.claim_stage(:crawling)
    SolidQueue::Job.enqueue(CrawlPagesJob.new(@first))

    assert_predicate Scan::Admission.new(@second), :queued?
  end

  test "a queued scan is left pending rather than started" do
    @first.claim_stage(:crawling)
    SolidQueue::Job.enqueue(CrawlPagesJob.new(@first))

    StartScanJob.perform_now(@second)

    assert_predicate @second.reload, :pending?
    assert_nil @second.started_at, "a scan that never began has no start time"
  end

  test "finishing a scan starts the one that has waited longest" do
    @first.claim_stage(:crawling)
    third = Scan.start!(Lead.for_website("https://later.test"))

    assert_enqueued_with(job: StartScanJob, args: [ @second ]) { @first.complete! }
    assert_predicate third.reload, :pending?, "only one is admitted, not both"
  end

  test "a failed scan frees the slot too" do
    @first.claim_stage(:crawling)

    assert_enqueued_with(job: StartScanJob, args: [ @second ]) { @first.fail!(stage: "crawling", error: "boom") }
  end

  test "a stalled scan does not hold the queue hostage" do
    # Its worker died and nothing will ever finish it. Counting it as live
    # would leave every later scan queued behind something already dead.
    @first.claim_stage(:crawling)

    assert_predicate @first.reload, :stalled?
    assert_predicate Scan::Admission.new(@second), :admit?
  end

  test "nothing is admitted while a scan is genuinely still working" do
    @first.claim_stage(:crawling)
    SolidQueue::Job.enqueue(CrawlPagesJob.new(@first))
    @first.update_columns(updated_at: 2.hours.ago)

    assert_no_enqueued_jobs(only: StartScanJob) { Scan::Admission.release! }
  end
end
