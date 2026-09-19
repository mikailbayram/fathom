require "test_helper"

class WebsiteIntelligenceTest < ActiveSupport::TestCase
  test "defaults to fake mode" do
    with_env("APP_MODE" => nil) { assert_equal :fake, WebsiteIntelligence.mode }
  end

  test "rejects an unknown mode rather than guessing" do
    with_env("APP_MODE" => "production") do
      assert_raises(WebsiteIntelligence::ConfigurationError) { WebsiteIntelligence.mode }
    end
  end

  test "credentials alone never enable live spending" do
    with_env("APP_MODE" => "live", "ENABLE_LIVE_AI" => nil, "OPENAI_API_KEY" => "sk-real", "FIRECRAWL_API_KEY" => "fc-real") do
      assert_predicate WebsiteIntelligence, :live?
      assert_not WebsiteIntelligence.live_ai_enabled?
      assert_not WebsiteIntelligence.external_requests_allowed?
    end
  end

  test "live spending requires both the mode and the explicit opt in" do
    with_env("APP_MODE" => "live", "ENABLE_LIVE_AI" => "true") do
      assert WebsiteIntelligence.live_ai_enabled?
    end

    with_env("APP_MODE" => "fake", "ENABLE_LIVE_AI" => "true") do
      assert_not WebsiteIntelligence.live_ai_enabled?, "fake mode never falls back to live"
    end
  end

  test "budgets zero dollars in fake mode" do
    assert_equal 0.0, WebsiteIntelligence.max_scan_ai_cost_usd
    assert_equal 0.0, WebsiteIntelligence.max_daily_ai_cost_usd
  end

  test "resolves vector width from the configured embedding model" do
    assert_equal 1536, WebsiteIntelligence.config.ai.embedding_dimensions

    WebsiteIntelligence.config.ai.embedding_model = "text-embedding-3-large"
    assert_equal 3072, WebsiteIntelligence.config.ai.embedding_dimensions
  end

  test "refuses to guess the vector width of an unknown model" do
    WebsiteIntelligence.config.ai.embedding_model = "some-new-model"

    assert_raises(WebsiteIntelligence::ConfigurationError) { WebsiteIntelligence.config.ai.embedding_dimensions }
  end

  test "routes model roles rather than literal ids" do
    with_env("AI_ANALYSIS_MODEL" => "gpt-experiment") do
      WebsiteIntelligence.reset_configuration!

      assert_equal "gpt-experiment", AI::Models.analysis.id
      assert_equal :analysis, AI::Models.analysis.role
      assert_equal "text-embedding-3-small", AI::Models.embedding.id
    end
  end

  test "routes the provider too, so leaving OpenAI is an environment change" do
    with_env("AI_PROVIDER" => "anthropic", "AI_ANALYSIS_MODEL" => "claude-sonnet-4.5") do
      WebsiteIntelligence.reset_configuration!

      assert_equal :anthropic, AI::Models.analysis.provider
      assert_equal "claude-sonnet-4.5", AI::Models.analysis.id
    end
  end

  test "routes every role to OpenAI by default" do
    WebsiteIntelligence.reset_configuration!

    assert_equal [ :openai ], AI::Models.all.values.map(&:provider).uniq
  end

  test "embeddings can stay with the provider that produced the stored vectors" do
    # Every vector in the database belongs to one model's space. Moving chat and
    # analysis off OpenAI must not silently move embeddings with them, or new
    # vectors stop being comparable to the ones already indexed.
    with_env("AI_PROVIDER" => "anthropic", "AI_EMBEDDING_PROVIDER" => "openai") do
      WebsiteIntelligence.reset_configuration!

      assert_equal :openai, AI::Models.embedding.provider
      assert_equal :anthropic, AI::Models.chat.provider
    end
  end

  test "embeddings follow the default provider when nothing pins them" do
    with_env("AI_PROVIDER" => "anthropic") do
      WebsiteIntelligence.reset_configuration!

      assert_equal :anthropic, AI::Models.embedding.provider
    end
  end

  test "carries reasoning effort on the chat role and nowhere else" do
    # Chat is the only call someone sits and waits on. Analysis and extraction
    # run behind a scan, where spending reasoning tokens is the right trade.
    WebsiteIntelligence.reset_configuration!

    assert_equal :medium, AI::Models.chat.effort
    assert_nil AI::Models.analysis.effort
    assert_nil AI::Models.fast.effort
    assert_nil AI::Models.embedding.effort
  end

  test "an empty chat effort sends none, leaving the provider its own default" do
    with_env("AI_CHAT_EFFORT" => "") do
      WebsiteIntelligence.reset_configuration!

      assert_nil AI::Models.chat.effort
    end
  end

  test "chat effort is an environment change like every other routing decision" do
    with_env("AI_CHAT_EFFORT" => "low") do
      WebsiteIntelligence.reset_configuration!

      assert_equal :low, AI::Models.chat.effort
    end
  end

  test "hands RubyLLM the key belonging to the provider in use" do
    with_env("AI_PROVIDER" => "anthropic", "ANTHROPIC_API_KEY" => "sk-ant-test") do
      WebsiteIntelligence.reset_configuration!

      assert_equal({ anthropic_api_key: "sk-ant-test" }, WebsiteIntelligence.ai_credentials)
    end
  end

  test "demands a key for every provider in use, and none for those that are not" do
    # Moving every role to another provider should stop requiring an OpenAI key,
    # and pinning embeddings back to OpenAI should start requiring it again.
    with_env("AI_PROVIDER" => "anthropic", "ANTHROPIC_API_KEY" => "sk-ant-test",
             "AI_EMBEDDING_PROVIDER" => "openai", "OPENAI_API_KEY" => nil) do
      WebsiteIntelligence.reset_configuration!

      error = assert_raises(WebsiteIntelligence::ConfigurationError) { WebsiteIntelligence.ai_credentials }
      assert_match(/OPENAI_API_KEY is not set/, error.message)
    end
  end

  test "names the provider when its key is missing rather than failing at the first call" do
    with_env("AI_PROVIDER" => "anthropic", "ANTHROPIC_API_KEY" => nil) do
      WebsiteIntelligence.reset_configuration!

      error = assert_raises(WebsiteIntelligence::ConfigurationError) { WebsiteIntelligence.ai_credentials }
      assert_match(/ANTHROPIC_API_KEY is not set/, error.message)
      assert_match(/:anthropic/, error.message)
    end
  end
end
