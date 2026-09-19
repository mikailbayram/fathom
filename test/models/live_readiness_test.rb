require "test_helper"

class LiveReadinessTest < ActiveSupport::TestCase
  test "fake mode needs no credentials" do
    with_env("FIRECRAWL_API_KEY" => nil, "OPENAI_API_KEY" => nil) do
      assert_predicate LiveReadiness.new, :ready?
      assert_empty LiveReadiness.new.missing
    end
  end

  test "live mode names exactly what is missing" do
    with_env("FIRECRAWL_API_KEY" => nil, "OPENAI_API_KEY" => nil) do
      WebsiteIntelligence.stub_mode(:live) do
        assert_not LiveReadiness.new.ready?
        assert_equal %w[FIRECRAWL_API_KEY OPENAI_API_KEY], LiveReadiness.new.missing
        assert_match(/FIRECRAWL_API_KEY and OPENAI_API_KEY/, LiveReadiness.new.message)
        assert_match(/Purpose: mapping\/crawling public websites/, LiveReadiness.new.checklist)
      end
    end
  end

  test "live mode names only the credential that is actually missing" do
    with_env("FIRECRAWL_API_KEY" => "fc-key", "OPENAI_API_KEY" => nil) do
      WebsiteIntelligence.stub_mode(:live) do
        assert_equal %w[OPENAI_API_KEY], LiveReadiness.new.missing
      end
    end
  end

  test "live mode is ready once both credentials exist" do
    with_env("FIRECRAWL_API_KEY" => "fc-key", "OPENAI_API_KEY" => "sk-key") do
      WebsiteIntelligence.stub_mode(:live) { assert_predicate LiveReadiness.new, :ready? }
    end
  end
end
