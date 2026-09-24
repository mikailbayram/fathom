# frozen_string_literal: true

module AI
  # Keeps provider calls far enough apart to stay inside a per-minute limit.
  #
  #   AI::Pace.wait_for(model)   # returns once it is this call's turn
  #
  # Providers meter requests per minute per model, and that is not a ceiling
  # concurrency can respect: OpenRouter allows a new account 20 requests a
  # minute, while an analysis call takes about two and a half seconds, so even
  # one strictly sequential stream runs at twenty-four a minute. There is no
  # concurrency setting low enough. Only spacing the calls works.
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
    # Requests per minute, by model role.
    DEFAULT_LIMIT = 20

    # The roles that are never spaced, for two different reasons.
    #
    # Embeddings are a different model on a different account and have never
    # been the constraint; pacing them would slow every retrieval for nothing.
    #
    # Chat is excluded because of how the spacing works rather than because it
    # is cheap. wait_for reserves the next free slot, so a question asked while
    # a scan already holds fifty reservations would wait fifty intervals --
    # two and a half minutes -- before it was even sent. The one call a person
    # is sitting in front of cannot queue behind batch work. A visitor's
    # question is rate limited at the endpoint instead, and a refusal from the
    # provider is retried by Client.
    UNPACED_ROLES = %i[embedding chat].freeze

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
        return 0.0 if UNPACED_ROLES.include?(model.role)

        limit = requests_per_minute
        limit.positive? ? 60.0 / limit : 0.0
      end

      private
        def requests_per_minute = WebsiteIntelligence.config.provider_requests_per_minute

        def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
