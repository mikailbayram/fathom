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
