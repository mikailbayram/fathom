# frozen_string_literal: true

# Base class for every stage of a scan.
#
# A stage that keeps failing marks the scan failed *and names the stage*, so the
# UI can say "mapping failed" rather than "something went wrong", and so a
# salesperson knows whether to retry or give up on the domain.
class PipelineJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    scan = job.arguments.first
    scan = scan.scan if scan.respond_to?(:scan)
    scan&.fail!(stage: job.stage, error: error)
    Rails.logger.error("#{job.class.name} gave up on scan #{scan&.id}: #{error.class}: #{error.message}")
  end

  # The pipeline stage this job belongs to, used for failure reporting.
  def stage = self.class.name.underscore.delete_suffix("_job")

  # A scan created in one mode must not be executed in another.
  #
  # A worker left running in fake mode will happily pick up a live scan and fill
  # it with fixture content, which is indistinguishable from a real result until
  # someone reads the URLs closely. Failing the scan is the only honest outcome.
  class ModeMismatch < StandardError; end

  def ensure_mode!(scan)
    running = WebsiteIntelligence.mode.to_s
    return if scan.mode == running

    raise ModeMismatch, "Scan ##{scan.id} was created in #{scan.mode} mode but this worker is in " \
                        "#{running} mode. Restart the worker, or rescan."
  end

  private
    def advance(scan) = scan.pipeline.advance!
end
