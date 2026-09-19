require "test_helper"

class ExternalRequestsTest < ActiveSupport::TestCase
  test "blocks outbound requests in fake mode" do
    assert_not ExternalRequests.allowed?

    error = assert_raises(WebsiteIntelligence::ExternalRequestBlocked) { ExternalRequests.guard!("Firecrawl /map") }
    assert_match(/Firecrawl \/map/, error.message)
    assert_match(/fake mode/, error.message)
  end

  test "the live crawler cannot reach the network in fake mode" do
    with_env("FIRECRAWL_API_KEY" => "fc-real-key") do
      assert_raises(WebsiteIntelligence::ExternalRequestBlocked) { Crawler::Firecrawl.new.map("https://example.com") }
      assert_raises(WebsiteIntelligence::ExternalRequestBlocked) { Crawler::Firecrawl.new.fetch("https://example.com") }
    end
  end

  test "the live embedder cannot reach the network in fake mode" do
    assert_raises(WebsiteIntelligence::ExternalRequestBlocked) { AI::Embedder::Live.new.embed([ "text" ]) }
  end

  test "the live AI client cannot reach the network in fake mode" do
    client = AI::Client.new(model: AI::Models.analysis, operation: "company_analysis")

    assert_raises(WebsiteIntelligence::ExternalRequestBlocked) do
      client.text(instructions: "x", prompt: "y")
    end
  end

  test "the crawler built in fake mode is the fixture crawler" do
    assert_instance_of Crawler::Fake, Crawler::Client.build
  end

  test "a missing credential is reported rather than assumed" do
    assert_not Crawler::Firecrawl.new(api_key: nil).configured?
    assert Crawler::Firecrawl.new(api_key: "fc-key").configured?

    error = assert_raises(Crawler::Client::Error) { Crawler::Firecrawl.new(api_key: nil).validate_credential! }
    assert_match(/FIRECRAWL_API_KEY/, error.message)
  end
end
