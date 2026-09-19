# frozen_string_literal: true

# Fan-out: every extracted claim gets checked against the buyer-visible corpus.
#
# One claim failing must not cost the scan the rest, which is why the work is
# split rather than looped here.
class CheckVisibilityJob < PipelineJob
  def stage = "checking_visibility"

  def perform(scan)
    ensure_mode!(scan)
    claims = scan.claims.unresolved.to_a
    return advance(scan) if claims.empty?

    claims.each { |claim| CheckClaimVisibilityJob.perform_later(claim) }
  end
end
