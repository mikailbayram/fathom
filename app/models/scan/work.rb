# frozen_string_literal: true

class Scan
  # Solid Queue owns job liveness, including retries and worker-death detection.
  # Inspect its existing arguments so jobs enqueued before this code still count.
  class Work
    def initialize(scan)
      @scan = scan
    end

    # Unknown when the queue has not been installed; never infer a dead worker
    # from an unavailable queue or the age of a scan's progress timestamp.
    def pending?
      jobs.where(finished_at: nil).where.missing(:failed_execution).exists? if available?
    end

    # Throws away this scan's queued work. A claimed job is already running on
    # a worker thread and is left alone: killing it mid-fetch would leave a page
    # half-written, and PipelineJob stops it at the next stage boundary anyway.
    def discard_pending!
      return 0 unless available?

      pending = jobs.where(finished_at: nil).where.missing(:claimed_execution).to_a
      pending.each(&:discard)
      pending.size
    end

    def blocked?
      available? && jobs.joins(:blocked_execution).exists?
    end

    private
      attr_reader :scan

      def available? = SolidQueue::Job.table_exists?

      def jobs
        references = [ scan.to_global_id.to_s ] + scan.claims.pluck(:id).map do |id|
          URI::GID.build(app: GlobalID.app, model_name: "Claim", model_id: id).to_s
        end

        SolidQueue::Job.where("arguments::jsonb #>> '{arguments,0,_aj_globalid}' IN (?)", references)
      end
  end
end
