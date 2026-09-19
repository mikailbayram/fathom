require "test_helper"

class Crawler::FirecrawlTest < ActiveSupport::TestCase
  # The v2 prefix was silently dropped for a while: Faraday *replaces* the base
  # path when a request path begins with "/", so "/map" against ".../v2" went to
  # api.firecrawl.dev/map and 404ed. Nothing but a live call could catch that,
  # which is exactly why the built URL is asserted here instead.
  test "builds request URLs under the versioned API prefix" do
    connection = Crawler::Firecrawl.new(api_key: "fc-test").send(:connection)

    assert_equal "https://api.firecrawl.dev/v2/", connection.url_prefix.to_s
    assert_equal "https://api.firecrawl.dev/v2/map", connection.build_url("map").to_s
    assert_equal "https://api.firecrawl.dev/v2/scrape", connection.build_url("scrape").to_s
  end

  test "the local crawler keeps that behaviour whatever URL it is given" do
    with_env("LOCAL_CRAWLER_URL" => "http://localhost:3002/v2") do
      connection = Crawler::Local.new.send(:connection)

      assert_equal "http://localhost:3002/v2/", connection.url_prefix.to_s
      assert_equal "http://localhost:3002/v2/map", connection.build_url("map").to_s
    end
  end

  test "reports a missing credential rather than calling out" do
    error = assert_raises(Crawler::Client::Error) { Crawler::Firecrawl.new(api_key: nil).validate_credential! }

    assert_match(/FIRECRAWL_API_KEY/, error.message)
  end

  # assume_model_exists requires an explicit provider; without one RubyLLM
  # raises ArgumentError before a request is ever made.
  test "every model role carries the provider RubyLLM needs" do
    AI::Models.all.each_value { |model| assert_equal :openai, model.provider, model.id }
  end
end
