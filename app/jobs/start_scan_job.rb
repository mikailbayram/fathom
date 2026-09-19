# frozen_string_literal: true

# The entry point. Everything after this is decided by the pipeline reading the
# database, never by this job.
class StartScanJob < PipelineJob
  def stage = "mapping"

  def perform(scan)
    ensure_mode!(scan)

    # A queued scan is left exactly as it is -- pending, with no started_at --
    # and Scan::Admission starts it when the running scan finishes. Nothing is
    # scheduled for it in the meantime, so there is no job sitting on a worker
    # thread waiting for a turn.
    return if Scan::Admission.new(scan).queued?

    scan.update!(started_at: Time.current, failed_at: nil, failed_stage: nil, error_message: nil)
    advance(scan)
  end
end
