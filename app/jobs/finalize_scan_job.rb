# frozen_string_literal: true

# Closes out a scan: settles the counters the UI reads and marks it complete.
class FinalizeScanJob < PipelineJob
  def stage = "scoring"

  def perform(scan)
    ensure_mode!(scan)
    scan.with_lock do
      # Reload under the lock so two finalizers cannot both release the slot.
      return if scan.finished?

      scan.update!(
        urls_discovered: scan.discovered_urls.count,
        pages_selected: scan.discovered_urls.selected.count,
        pages_crawled: scan.pages.count,
        pages_indexed: scan.pages.indexed.count,
        chunks_count: scan.chunks.count,
        claims_count: scan.claims.count,
        # Only viable findings are counted: a question we tested and could not
        # answer is not an opportunity.
        findings_count: scan.findings.viable.count
      )

      scan.complete!
    end
  end
end
