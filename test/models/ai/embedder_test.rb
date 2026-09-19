require "test_helper"

class AI::EmbedderTest < ActiveSupport::TestCase
  setup { @embedder = AI::Embedder.build }

  test "fake mode never builds a live provider, even with a key in the environment" do
    with_env("OPENAI_API_KEY" => "sk-should-be-ignored") do
      assert_instance_of AI::Embedder::Fake, AI::Embedder.build
    end
  end

  test "produces vectors of the configured width" do
    vector = @embedder.embed_one("custom RBAC roles")

    assert_equal WebsiteIntelligence.config.ai.embedding_dimensions, vector.size
  end

  test "is deterministic across calls and instances" do
    assert_equal @embedder.embed_one("SCIM provisioning"), AI::Embedder.build.embed_one("SCIM provisioning")
  end

  test "produces unit vectors" do
    magnitude = Math.sqrt(@embedder.embed_one("webhook retries").sum { |value| value * value })

    assert_in_delta 1.0, magnitude, 0.0001
  end

  test "handles empty and stopword-only text without producing a zero vector" do
    [ "", "   ", "the and of" ].each do |text|
      vector = @embedder.embed_one(text)

      assert_equal WebsiteIntelligence.config.ai.embedding_dimensions, vector.size
      assert_operator vector.sum { |value| value.abs }, :>, 0
    end
  end

  test "places texts that share vocabulary closer than texts that do not" do
    roles = @embedder.embed_one("custom RBAC roles with granular resource permissions")
    similar = @embedder.embed_one("administrators define custom roles with granular permissions")
    unrelated = @embedder.embed_one("we are hiring designers in Berlin and Lisbon")

    assert_operator cosine(roles, similar), :>, cosine(roles, unrelated)
  end

  test "embeds a batch in one call" do
    vectors = @embedder.embed([ "one", "two", "three" ])

    assert_equal 3, vectors.size
    assert_equal @embedder.embed_one("two"), vectors[1]
  end

  test "records usage even though nothing was spent" do
    scan = acme_scan

    assert_difference -> { AIUsage.count }, 1 do
      AI::Embedder.build(scan: scan).embed([ "custom roles" ])
    end

    usage = AIUsage.last
    assert_equal "embedding", usage.operation
    assert_equal "fake", usage.provider
    assert_equal 0, usage.estimated_cost
  end

  private
    def cosine(a, b) = a.each_with_index.sum { |value, index| value * b[index] }
end
