# frozen_string_literal: true

module AI
  # The only place RubyLLM is called. Every live request passes the external
  # request guard and the spending limit, and every response is recorded in
  # ai_usages from the provider's own usage metadata.
  class Client
    class ResponseError < StandardError; end

    # A rate limit is a queueing problem, not a failure. Stages fan out several
    # calls at once and a metered account answers the burst with a 429, which is
    # the first thing a new key tends to meet. Failing the scan there would
    # throw away every passage already read.
    #
    # Waits are long because the window being waited out is a minute: a burst of
    # six concurrent calls needs the limit to actually roll over, not a quick
    # retry into the same wall.
    RATE_LIMIT_ATTEMPTS = 5
    RATE_LIMIT_BACKOFF = [ 5, 15, 30, 60 ].freeze

    # Defined on the class so a test can exercise the retry policy without
    # actually waiting out a provider's minute.
    def self.pause(seconds) = sleep(seconds)

    def initialize(model:, operation:, scan: nil, conversation: nil)
      @model = model
      @operation = operation
      @scan = scan
      @conversation = conversation
    end

    # tools are the RubyLLM::Tool instances the model may call before it
    # answers; stream, when given, is fed every chunk as the reply arrives and
    # must respond to #call and #reset.
    def structured(schema:, instructions:, prompt:, tools: [], stream: nil)
      parsed = complete(instructions: instructions, prompt: prompt, schema: schema,
                        tools: tools, stream: stream).parsed
      raise ResponseError, "#{model.id} returned no structured output for #{operation}" if parsed.blank?

      parsed.deep_stringify_keys
    end

    def text(instructions:, prompt:)
      complete(instructions: instructions, prompt: prompt).content.to_s
    end

    private
      attr_reader :model, :operation, :scan, :conversation

      def complete(instructions:, prompt:, schema: nil, tools: [], stream: nil)
        attempt = 0

        begin
          attempt += 1
          request(instructions: instructions, prompt: prompt, schema: schema, tools: tools, stream: stream)
        rescue RubyLLM::RateLimitError => error
          raise ResponseError, "#{model.id} is rate limited during #{operation}: #{error.message}" if
            attempt >= RATE_LIMIT_ATTEMPTS

          self.class.pause(RATE_LIMIT_BACKOFF[attempt - 1] || RATE_LIMIT_BACKOFF.last)
          # The next attempt writes the answer again from the top, so whatever
          # this one had begun to show is withdrawn rather than continued.
          stream&.reset
          retry
        end
      end

      def request(instructions:, prompt:, schema: nil, tools: [], stream: nil)
        ExternalRequests.guard!("#{operation} via #{model.id}")
        SpendingLimit.new(scan: scan).enforce!

        # Every call goes through here, whichever stage or job made it, which is
        # the only place the account's per-minute limit can actually be seen.
        Pace.wait_for(model)

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # The configured model IDs are deliberately not looked up in RubyLLM's
        # registry: model routing is ours to decide, not the gem's to validate.
        chat = RubyLLM.chat(model: model.id, provider: model.provider, assume_model_exists: true)
        chat.with_thinking(effort: model.effort) if model.effort
        chat.with_provider_options(usage_accounting) if usage_accounting
        chat.with_instructions(instructions)
        chat.with_schema(schema) if schema
        chat.with_tools(*tools) if tools.any?

        message = stream ? chat.ask(prompt) { |chunk| stream.call(chunk) } : chat.ask(prompt)
        record(chat, started)
        message
      # Ordered before the catch-all deliberately: RateLimitError is a
      # RubyLLM::Error, and wrapping it here would hide it from the retry above.
      rescue RubyLLM::RateLimitError
        raise
      rescue RubyLLM::Error => error
        raise ResponseError, "#{model.id} failed during #{operation}: #{error.message}"
      end

      # Because the model IDs above are never looked up in RubyLLM's registry,
      # nothing local knows what a call costs -- the price has to come back with
      # the response. OpenAI prices from the registry, but an aggregator bills
      # its own rates and only reports them when asked. Without this the usage
      # ledger records nulls, SpendingLimit reads those as zero, and a scan runs
      # to the end of a site with no budget in force at all.
      def usage_accounting
        { usage: { include: true } } if model.provider.to_sym == :openrouter
      end

      # Read from the chat rather than from the reply it returned, because a
      # call that used a tool made more than one request and the reply carries
      # only the last of them -- for the chatbot, roughly half of what the
      # question actually cost. Chat aggregates every request it made, and
      # reports no total at all when any of them came back unpriced, which is
      # what keeps unknown from being recorded as zero.
      def record(chat, started)
        AIUsage.record(
          operation: operation,
          provider: model.provider,
          model: model.id,
          scan: scan,
          conversation: conversation,
          input_tokens: chat.tokens&.input,
          output_tokens: chat.tokens&.output,
          estimated_cost: chat.cost&.total,
          duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000).round
        )
      end
  end
end
