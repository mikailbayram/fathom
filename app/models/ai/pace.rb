# frozen_string_literal: true

module AI
  # Keeps provider calls far enough apart to stay inside a per-minute limit.
  #
  #   AI::Pace.wait_for(model)   # returns once it is this call's turn
  #
  # OpenAI meters requests per minute per model, and that is not a ceiling
  # concurrency can respect: at the 20 requests a minute this defaults to, and
  # an analysis call taking about two and a half seconds, even one strictly
  # sequential stream runs at twenty-four a minute. There is no concurrency
  # setting low enough. Only spacing the calls works.
  #
  # Retrying a rejected call is still necessary -- see Client's backoff -- but a
  # retry is what happens when this failed. Waiting three seconds beats being
  # refused and sleeping thirty.
  #
  # LIMITATION: this paces one process. It is correct while the application runs
  # a single worker (JOB_CONCURRENCY=1, which config/queue.yml defaults to);
  # with two worker processes each would pace itself and the account would see
  # double. Moving the timestamp into a row claimed with an advisory lock is the
  # fix, and is worth doing the day a second worker exists, not before.
  module Pace
    # Requests per minute, by model role. Embeddings are excluded on purpose:
    # they are a different model on a far higher limit and have never been the
    # constraint, and pacing them would slow every retrieval for nothing.
    DEFAULT_LIMIT = 20

    @mutex = Mutex.new
    @next_allowed = {}

    class << self
      # Blocks until enough time has passed since the last call for this model,
      # then reserves this call's slot. Reserving before returning is what makes
      # concurrent callers queue behind one another rather than all measuring
      # from the same last call and leaving together.
      def wait_for(model)
        interval = interval_for(model)
        return if interval.zero?

        slot = @mutex.synchronize do
          earliest = [ @next_allowed[model.id].to_f, now ].max
          @next_allowed[model.id] = earliest + interval
          earliest
        end

        delay = slot - now
        sleep(delay) if delay.positive?
      end

      # Test seam, and what a process restart would do anyway.
      def reset!
        @mutex.synchronize { @next_allowed = {} }
      end

      def interval_for(model)
        return 0.0 if model.role == :embedding

        limit = requests_per_minute
        limit.positive? ? 60.0 / limit : 0.0
      end

      private
        def requests_per_minute = WebsiteIntelligence.config.provider_requests_per_minute

        def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
