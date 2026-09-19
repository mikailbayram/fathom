# frozen_string_literal: true

class Scan
  # Decides which scan is allowed to run, and starts the next one when a slot
  # frees.
  #
  #   Scan::Admission.new(scan).admit?   # may this scan begin now?
  #   Scan::Admission.release!           # a scan finished; start whoever is next
  #
  # A scan is not one job but a chain of a dozen, so Solid Queue's concurrency
  # limit cannot express this: its semaphore is held for a single execution, and
  # StartScanJob finishes in milliseconds. The limit there would release before
  # the scan it admitted had crawled a single page.
  #
  # Running several scans at once was not merely slow. They share one crawler
  # account and one provider account, both metered per minute, so three scans
  # spent most of their time being refused and retried -- the work took longer
  # in total than doing them one after another.
  class Admission
    def initialize(scan)
      @scan = scan
    end

    # A scan may start when no other scan is live. A stalled scan does not
    # count: its worker died, nothing will finish it, and treating it as live
    # would leave every later scan queued behind a corpse.
    def admit? = other_live_scans.none?

    def queued? = !admit?

    # Starts the scan that has waited longest, if any, and if nothing else is
    # running. Called when a scan reaches an end state.
    def self.release!
      return if live_scans.any?

      waiting = Scan.where(status: :pending).order(:created_at).first
      StartScanJob.perform_later(waiting) if waiting
    end

    # Live means started and not finished. Stalled scans are excluded here
    # rather than at the call sites, so every caller agrees on the definition.
    def self.live_scans
      Scan.where(status: Scan::STAGES).reject(&:stalled?)
    end

    private
      attr_reader :scan

      def other_live_scans = self.class.live_scans.reject { |other| other.id == scan.id }
  end
end
