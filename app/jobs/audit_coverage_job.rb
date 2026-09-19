# frozen_string_literal: true

# Records the enterprise topics a company answers nowhere at all.
#
# Runs after the buried facts are scored, so a scan that found nothing buried
# still has something true and useful to say.
class AuditCoverageJob < PipelineJob
  def stage = "auditing_coverage"

  def perform(scan)
    ensure_mode!(scan)
    return advance(scan) if scan.reload.coverage_audited_at?

    gaps = CoverageAudit.new(scan).gaps

    scan.with_lock do
      # A retry or an older duplicate may finish after another execution.
      # Persist the audit once, including its claims, in the same transaction.
      return advance(scan) if scan.coverage_audited_at?

      scan.findings.where(kind: "missing").destroy_all

      gaps.each do |gap|
        claim = scan.claims.create!(
          statement: "Nothing on #{scan.domain} addresses #{gap.topic}.",
          question_text: gap.question,
          category: gap.category,
          buyer_importance: gap.importance,
          topic: gap.topic,
          support: 0.0,
          status: "checked"
        )

        finding = claim.create_finding!(
          scan: scan,
          kind: "missing",
          topic: gap.topic,
          answer: nil,
          buyer_visible_answer: nil,
          why_it_matters: "An enterprise buyer will ask this during evaluation. #{scan.lead.name} answers it " \
                          "nowhere in the public content we indexed, so the question reaches their sales team " \
                          "-- or stalls the deal.",
          answer_confidence: 0.0,
          buyer_importance: gap.importance,
          full_corpus_confidence: 0.0,
          buyer_visible_confidence: gap.confidence,
          status: "viable"
        )
        finding.update!(FrictionScore.new(finding).to_attributes)
      end

      scan.update!(coverage_audited_at: Time.current)
    end

    advance(scan)
  end
end
