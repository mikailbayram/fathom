# frozen_string_literal: true

# Applies the deterministic friction score to one finding.
#
# Nothing here calls a model. The inputs came from the answering stage; the
# arithmetic is ours, and is unit tested.
class ScoreFindingJob < ApplicationJob
  queue_as :default

  def perform(finding)
    finding.update!(FrictionScore.new(finding).to_attributes)

    scan = finding.scan
    scan.pipeline.advance! unless scan.findings.pending.exists?
  end
end
