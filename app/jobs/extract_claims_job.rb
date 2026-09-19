# frozen_string_literal: true

# Reads the deep corpus and records the checkable claims the company published.
#
# This replaces asking a fixed list of questions. What a scan finds is now
# bounded by what the company actually wrote, not by what we thought to ask.
class ExtractClaimsJob < PipelineJob
  def stage = "extracting_claims"

  def perform(scan)
    ensure_mode!(scan)
    claims = AI::Extractor.build(scan).claims

    Claim.transaction do
      scan.claims.destroy_all
      claims.each do |claim|
        # A duplicate statement from a second passage is the same claim.
        scan.claims.create(claim.to_attributes(scan))
      end
      scan.update!(claims_count: scan.claims.count, claims_extracted_at: Time.current)
    end

    advance(scan)
  end
end
