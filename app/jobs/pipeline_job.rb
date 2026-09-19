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

  # Stop means stop, not "stop after this stage".
  #
  # Discarding the queue cannot reach a job a worker has already claimed, so
  # every stage checks the scan before it does anything. Without this, stopping
  # during the crawl would still leave a company analysis and an embedding bill
  # behind it.
  around_perform do |job, block|
    scan = job.scan_for_arguments
    next if scan&.reload&.finished?

    block.call
  end

  # Stages take a scan, a claim or a finding; all three can name their scan.
  def scan_for_arguments
    subject = arguments.first
    subject.respond_to?(:scan) ? subject.scan : subject
  rescue ActiveRecord::RecordNotFound
    nil
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
