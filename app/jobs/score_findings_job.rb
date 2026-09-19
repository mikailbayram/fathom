# frozen_string_literal: true

# Stage nine, fan-out: score every finding that has not been scored yet.
class ScoreFindingsJob < PipelineJob
  def stage = "scoring"

  def perform(scan)
    ensure_mode!(scan)
    findings = scan.findings.pending.to_a
    return advance(scan) if findings.empty?

    findings.each { |finding| ScoreFindingJob.perform_later(finding) }
  end
end
