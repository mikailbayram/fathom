# frozen_string_literal: true

# Stage six: understand the company from its own indexed content.
class AnalyzeCompanyJob < PipelineJob
  def stage = "analyzing"

  def perform(scan)
    ensure_mode!(scan)
    profile = AI::Analyst.build(scan).profile

    record = scan.company_profile || scan.build_company_profile
    record.update!(profile.to_attributes)

    advance(scan)
  end
end
