# frozen_string_literal: true

# Central configuration for the website friction intelligence pipeline.
#
# Every tunable the pipeline depends on lives here so that model routing, crawl
# budgets, retrieval widths and scoring thresholds are configuration changes
# rather than edits scattered through jobs and services.
module WebsiteIntelligence
  MODES = %i[fake local live].freeze

  # Vector widths for the embedding models we know about. An unknown model must
  # declare its width through AI_EMBEDDING_DIMENSIONS rather than be guessed at,
  # because the chunks.embedding column has to match exactly.
  KNOWN_EMBEDDING_DIMENSIONS = {
    "text-embedding-3-small" => 1536,
    "text-embedding-3-large" => 3072,
    "text-embedding-ada-002" => 1536
  }.freeze

  class ConfigurationError < StandardError; end

  # Raised whenever code attempts an outbound provider call that the current
  # application mode forbids. Fake mode never falls back to live mode: it fails.
  class ExternalRequestBlocked < StandardError; end

  class AiConfiguration
    attr_accessor :provider, :embedding_model, :fast_model, :analysis_model, :chat_model, :chat_effort
    attr_writer :embedding_dimensions, :embedding_provider

    def initialize
      @provider = ENV.fetch("AI_PROVIDER", "openai").to_sym
      @embedding_model = ENV.fetch("AI_EMBEDDING_MODEL", "text-embedding-3-small")
      @fast_model = ENV.fetch("AI_FAST_MODEL", "gpt-5.6-luna")
      @analysis_model = ENV.fetch("AI_ANALYSIS_MODEL", "gpt-5.6-terra")
      @chat_model = ENV.fetch("AI_CHAT_MODEL", "gpt-5.6-terra")

      # Reasoning effort, and only for chat. This is the one call a person is
      # sitting and waiting on: every other role is batch work behind a scan,
      # where accuracy is worth whatever the wait costs. The reply is capped at
      # a few sentences either way, so the reasoning tokens are most of what
      # the visitor is waiting for rather than the answer itself.
      #
      # Blank sends no effort at all and lets the provider pick its default.
      @chat_effort = ENV.fetch("AI_CHAT_EFFORT", "medium").presence&.to_sym
      @embedding_provider = ENV["AI_EMBEDDING_PROVIDER"].presence&.to_sym
      @embedding_dimensions = ENV["AI_EMBEDDING_DIMENSIONS"]&.to_i
    end

    # Embeddings get their own provider setting because they are the one role
    # that cannot be switched freely. Every vector already in the database was
    # produced by one model in one vector space; point this somewhere else and
    # the stored embeddings stop being comparable to new ones, so every scan has
    # to be re-indexed. Moving chat and analysis to another provider while
    # embeddings stay where they are is the change that costs nothing.
    def embedding_provider = @embedding_provider || provider

    def embedding_dimensions
      @embedding_dimensions ||
        KNOWN_EMBEDDING_DIMENSIONS[embedding_model] ||
        raise(ConfigurationError, <<~MESSAGE)
          Unknown vector width for embedding model #{embedding_model.inspect}.
          Set AI_EMBEDDING_DIMENSIONS to the model's documented output size.
        MESSAGE
    end
  end

  class Configuration
    attr_accessor :max_concurrent_scans,
                  :max_classified_urls,
                  :max_claim_passages,
                  :max_claims_per_scan,
                  :claim_extraction_batch,
                  :provider_call_concurrency,
                  :provider_requests_per_minute,
                  :chunk_target_tokens,
                  :chunk_overlap_tokens,
                  :semantic_results,
                  :lexical_results,
                  :final_retrieval_results,
                  :minimum_answer_confidence,
                  :minimum_finding_score,
                  :max_discovered_urls,
                  :max_pages_per_scan,
                  :max_scan_ai_cost_usd,
                  :max_daily_ai_cost_usd,
                  :crawl_cost_per_request_usd,
                  :crawl_concurrency,
                  :embedding_batch_size,
                  :public_demo_rate_limit,
                  :public_demo_rate_period

    attr_reader :ai

    def initialize
      @ai = AiConfiguration.new

      # Extraction reads the deep passages most likely to hold enterprise facts,
      # not all of them: a large documentation site has tens of thousands of
      # passages and almost all of them say nothing a buyer would evaluate on.
      # Scans run against one metered crawler account and one AI budget. Letting
      # every submitted scan start at once means they all crawl slowly, cost
      # more in refused requests, and finish later than if they had queued.
      @max_concurrent_scans = Integer(ENV.fetch("MAX_CONCURRENT_SCANS", 3))

      # Classification is the one stage whose cost scales with how big a site
      # is rather than with how much of it we intend to read. Autodesk mapped
      # 5,165 URLs, 1,507 of them unrecognised; classifying all of them costs
      # real money to label pages the crawl budget would never reach.
      @max_classified_urls = Integer(ENV.fetch("MAX_CLASSIFIED_URLS", 400))
      @max_claim_passages = Integer(ENV.fetch("MAX_CLAIM_PASSAGES", 400))
      @max_claims_per_scan = Integer(ENV.fetch("MAX_CLAIMS_PER_SCAN", 120))
      @claim_extraction_batch = 8

      # How many provider calls a single stage may have in flight. Extraction is
      # one call per batch of passages and the coverage audit is one per buyer
      # question -- dozens of independent requests, each spending its time
      # waiting on a socket. Run serially that is ten minutes of a salesperson
      # watching a progress bar. The ceiling is the database pool the worker
      # thread shares, not the provider.
      @provider_call_concurrency = Integer(ENV.fetch("AI_CALL_CONCURRENCY", 6))

      # The account's own per-minute ceiling for a chat model, which AI::Pace
      # spaces calls to stay under. Zero disables pacing entirely.
      @provider_requests_per_minute = Integer(ENV.fetch("AI_REQUESTS_PER_MINUTE", 20))

      @chunk_target_tokens = 750
      @chunk_overlap_tokens = 100

      @semantic_results = 15
      @lexical_results = 15
      @final_retrieval_results = 12

      @minimum_answer_confidence = 0.75
      @minimum_finding_score = 60

      @max_discovered_urls = 50_000
      @max_pages_per_scan = Integer(ENV.fetch("MAX_SCAN_PAGES", 5_000))

      @max_scan_ai_cost_usd = Float(ENV.fetch("MAX_SCAN_AI_COST_USD", 3.00))
      @max_daily_ai_cost_usd = Float(ENV.fetch("MAX_DAILY_AI_COST_USD", 10.00))

      # The crawler meters credits against an account and never prices a single
      # response, so what a scan cost to crawl can only be counted here and
      # multiplied. The default is one credit per request at Firecrawl's
      # published standard rate; an operator on another plan sets their own.
      @crawl_cost_per_request_usd = Float(ENV.fetch("CRAWL_COST_PER_REQUEST_USD", 0.001))

      @crawl_concurrency = 4
      @embedding_batch_size = 64

      @public_demo_rate_limit = 20
      @public_demo_rate_period = 3.minutes
    end
  end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
      config
    end

    # Test seam: lets a test exercise live-mode budgeting without setting
    # environment variables that other tests would then inherit.
    def stub_mode(mode)
      previous = @mode
      @mode = mode
      yield
    ensure
      @mode = previous
    end

    def reset_configuration!
      @config = nil
      @mode = nil
    end

    # fake  -- deterministic adapters, no outbound requests (default)
    # local -- locally hosted models/crawlers
    # live  -- real external providers
    def mode
      @mode ||= begin
        requested = ENV.fetch("APP_MODE", "fake").to_s.downcase.to_sym
        unless MODES.include?(requested)
          raise ConfigurationError, "APP_MODE must be one of #{MODES.join(', ')} (got #{requested.inspect})"
        end
        requested
      end
    end

    def fake? = mode == :fake
    def local? = mode == :local
    def live? = mode == :live

    # Credentials being present is never enough. Live spending additionally
    # requires the operator to opt in explicitly.
    def live_ai_enabled?
      live? && ActiveModel::Type::Boolean.new.cast(ENV.fetch("ENABLE_LIVE_AI", "false"))
    end

    def external_requests_allowed?
      live_ai_enabled?
    end

    # The providers this configuration actually routes to. Usually one -- OpenAI
    # -- and two only when embeddings are pinned to the provider that produced
    # the stored vectors while everything else has moved elsewhere.
    def active_ai_providers = [ config.ai.provider, config.ai.embedding_provider ].uniq

    # RubyLLM names every provider's key <provider>_api_key and reads it from
    # <PROVIDER>_API_KEY, so the pair is derived rather than tabulated -- adding
    # a provider is then an environment change like everything else here.
    #
    # Only the providers in use are demanded. Moving every role off OpenAI
    # should not keep requiring a key that nothing will spend.
    def ai_credentials
      active_ai_providers.to_h do |provider|
        variable = "#{provider.to_s.upcase}_API_KEY"
        key = ENV[variable].presence or raise ConfigurationError, <<~MESSAGE
          #{variable} is not set, but AI is routed through #{provider.inspect}.
          Set it, or point AI_PROVIDER at a provider you have credentials for.
        MESSAGE

        [ :"#{provider}_api_key", key ]
      end
    end

    # Fake mode budgets zero dollars, which keeps the spending guard meaningful
    # in development and CI rather than merely dormant.
    def max_scan_ai_cost_usd
      fake? ? 0.0 : config.max_scan_ai_cost_usd
    end

    def max_daily_ai_cost_usd
      fake? ? 0.0 : config.max_daily_ai_cost_usd
    end
  end
end
