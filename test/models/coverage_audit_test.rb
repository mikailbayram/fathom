require "test_helper"

class CoverageAuditTest < ActiveSupport::TestCase
  test "repeating a saved audit preserves its claims without calling providers again" do
    scan = indexed_acme_scan
    AuditCoverageJob.perform_now(scan)
    assert scan.reload.coverage_audited_at?
    claims = scan.claims.pluck(:id)
    findings = scan.findings.pluck(:id)

    with_stub(CoverageAudit, :new, ->(*) { raise "audit must not run twice" }) do
      AuditCoverageJob.perform_now(scan)
    end

    assert_equal claims, scan.claims.pluck(:id)
    assert_equal findings, scan.findings.pluck(:id)
  end

  test "asserts nothing when too little of the site was read" do
    # A scan that crawled nothing knows nothing. Reporting "they publish no SSO
    # documentation" from an empty index is an invention, not a finding.
    empty = acme_scan

    assert_not CoverageAudit.new(empty).corpus_sufficient?
    assert_empty CoverageAudit.new(empty).gaps
  end

  test "reports the topics a real corpus genuinely never covers" do
    scan = indexed_acme_scan
    ExtractClaimsJob.perform_now(scan)

    audit = CoverageAudit.new(scan)
    assert audit.corpus_sufficient?

    topics = audit.gaps.map(&:topic)
    assert_predicate topics, :any?
    assert_not_includes topics, "RBAC", "the documentation covers custom roles at length"
    assert_not_includes topics, "webhooks", "webhook retries are documented"
  end

  test "every gap names a question a buyer would actually ask" do
    scan = indexed_acme_scan
    ExtractClaimsJob.perform_now(scan)

    CoverageAudit.new(scan).gaps.each do |gap|
      assert_includes gap.question, "Acme"
      assert_includes Claim::CATEGORIES, gap.category
      assert_operator gap.importance, :>, 0.5
    end
  end

  test "overlapping the buyer questions does not change which gaps come out, or their order" do
    # Each question is an independent provider call of about twelve seconds, so
    # the audit runs them concurrently. Order still has to hold: the findings a
    # salesperson sees must not depend on which call returned first.
    scan = indexed_acme_scan
    ExtractClaimsJob.perform_now(scan)

    serial = with_call_concurrency(1) { CoverageAudit.new(scan).gaps }
    parallel = with_call_concurrency(6) { CoverageAudit.new(scan).gaps }

    assert_predicate serial, :any?, "the fixture has to produce gaps for this to prove anything"
    assert_equal serial.map(&:topic), parallel.map(&:topic)
    assert_equal serial.map(&:question), parallel.map(&:question)
  end

  private
    def with_call_concurrency(count)
      with_env("AI_CALL_CONCURRENCY" => count.to_s) { yield }
    end
end
