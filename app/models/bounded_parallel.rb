# frozen_string_literal: true

# Order-preserving parallel map over a bounded number of threads.
#
#   BoundedParallel.map(questions, limit: 6) { |question| answerer.answer(question) }
#
# Several pipeline stages are a loop of independent provider calls -- one per
# passage batch, one per checklist question -- and each call spends ten to
# twenty seconds waiting on a socket. Run in sequence that is minutes of a scan
# doing nothing; the work itself is not the cost, the waiting is.
#
# Order is preserved deliberately. Extraction deduplicates claims and caps them
# per scan, so a result that depended on which provider call returned first
# would make the same site produce different findings on different runs.
module BoundedParallel
  # Threads here do their own database writes -- the AI usage ledger -- so each
  # needs the executor to lend it a connection and return it afterwards.
  #
  # The first item to raise re-raises from #value, which is what the stage jobs
  # expect: a failed provider call should fail the stage rather than quietly
  # yield fewer results than there were inputs.
  def self.map(items, limit:, &block)
    items = items.to_a
    return items.map(&block) if limit.to_i <= 1 || items.one?

    items.each_slice(limit).flat_map do |wave|
      wave
        .map do |item|
          # #value re-raises here, so Ruby printing the same backtrace from
          # inside the thread as well is pure noise.
          Thread.new { Rails.application.executor.wrap { block.call(item) } }
                .tap { |thread| thread.report_on_exception = false }
        end
        .map(&:value)
    end
  end
end
