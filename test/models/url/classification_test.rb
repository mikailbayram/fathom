require "test_helper"

class Url::ClassificationTest < ActiveSupport::TestCase
  test "classifies high priority technical paths" do
    {
      "https://acme.com/docs/roles" => "docs",
      "https://acme.com/developers/api" => "developer_docs",
      "https://acme.com/api/v2/limits" => "developer_docs",
      "https://acme.com/security" => "security",
      "https://acme.com/trust/soc2" => "trust",
      "https://acme.com/pricing" => "pricing",
      "https://acme.com/integrations/netsuite" => "integration",
      "https://acme.com/help/billing" => "help_center",
      "https://acme.com/support" => "support"
    }.each do |url, expected|
      assert_equal expected, Url.new(url, domain: "acme.com").page_type, url
    end
  end

  test "classifies medium and low priority paths" do
    assert_equal "product", Url.new("https://acme.com/features/sync", domain: "acme.com").page_type
    assert_equal "solution", Url.new("https://acme.com/solutions/finance", domain: "acme.com").page_type
    assert_equal "legal", Url.new("https://acme.com/legal/dpa", domain: "acme.com").page_type
    assert_equal "blog", Url.new("https://acme.com/blog/post", domain: "acme.com").page_type
    assert_equal "careers", Url.new("https://acme.com/careers", domain: "acme.com").page_type
  end

  test "classifies PDFs regardless of where they live" do
    classification = Url.new("https://acme.com/resources/enterprise-guide.pdf", domain: "acme.com").classification

    assert_equal "pdf", classification.page_type
    assert_equal CorpusTypes::DEEP, classification.corpus_type
  end

  test "classifies known subdomains into the deep corpus" do
    {
      "https://docs.acme.com/" => "docs",
      "https://developers.acme.com/" => "developer_docs",
      "https://help.acme.com/article" => "help_center",
      "https://trust.acme.com/" => "trust",
      "https://support.acme.com/" => "support"
    }.each do |url, expected|
      classification = Url.new(url, domain: "acme.com").classification

      assert_equal expected, classification.page_type, url
      assert_equal CorpusTypes::DEEP, classification.corpus_type, url
    end
  end

  test "lets a path rule refine a subdomain's verdict" do
    assert_equal "developer_docs", Url.new("https://docs.acme.com/api/limits", domain: "acme.com").page_type
  end

  test "matches paths case insensitively" do
    assert_equal "pricing", Url.new("https://acme.com/Pricing", domain: "acme.com").page_type
  end

  test "treats the apex root as the homepage but not a subdomain root" do
    assert_equal "homepage", Url.new("https://www.acme.com/", domain: "acme.com").page_type
    assert_equal "docs", Url.new("https://docs.acme.com/", domain: "acme.com").page_type
  end

  test "assigns buyer visible and deep corpora" do
    assert_equal CorpusTypes::BUYER_VISIBLE, Url.new("https://acme.com/pricing", domain: "acme.com").corpus_type
    assert_equal CorpusTypes::BUYER_VISIBLE, Url.new("https://acme.com/security", domain: "acme.com").corpus_type
    assert_equal CorpusTypes::DEEP, Url.new("https://docs.acme.com/roles", domain: "acme.com").corpus_type
    assert_equal CorpusTypes::IGNORED, Url.new("https://acme.com/blog/post", domain: "acme.com").corpus_type
  end

  test "rejects urls outside the lead's domain" do
    classification = Url.new("https://twitter.com/acme", domain: "acme.com").classification

    assert_equal CorpusTypes::IGNORED, classification.corpus_type
    assert_equal 0, classification.priority
  end

  test "reports a lack of confidence only when no rule matched" do
    assert Url.new("https://acme.com/pricing", domain: "acme.com").confident?
    assert_not Url.new("https://acme.com/wombat-platform", domain: "acme.com").confident?
  end
end
