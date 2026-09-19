require "test_helper"

class UrlTest < ActiveSupport::TestCase
  test "canonicalizes scheme, host casing and the www prefix" do
    assert_equal "https://acme.com/pricing", Url.new("HTTPS://WWW.Acme.COM/pricing").canonical
    assert_equal "https://acme.com/pricing", Url.new("https://acme.com/pricing/").canonical
  end

  test "keeps the published host on the URL it will actually fetch" do
    assert_equal "https://www.acme.com/pricing", Url.new("https://WWW.acme.com/pricing/").to_s
  end

  test "strips fragments and default ports" do
    assert_equal "https://acme.com/docs", Url.new("https://acme.com:443/docs#section").canonical
    assert_equal "http://acme.com/docs", Url.new("http://acme.com:80/docs").canonical
  end

  test "removes tracking parameters but keeps parameters that identify content" do
    url = Url.new("https://acme.com/search?utm_source=news&gclid=x&q=rbac&page_id=4")

    assert_equal "https://acme.com/search?page_id=4&q=rbac", url.canonical
  end

  test "orders query parameters so order never creates a second identity" do
    assert_equal Url.new("https://acme.com/a?b=2&a=1").canonical, Url.new("https://acme.com/a?a=1&b=2").canonical
  end

  test "treats an explicit index document as the directory" do
    assert_equal "https://acme.com/docs", Url.new("https://acme.com/docs/index.html").canonical
  end

  test "rejects anything that is not a fetchable http resource" do
    [ "mailto:sales@acme.com", "javascript:alert(1)", "#anchor", "tel:+123", "", nil ].each do |input|
      assert_not Url.new(input).valid?, "#{input.inspect} should not be valid"
    end
  end

  test "resolves relative links against a base" do
    assert_equal "https://docs.acme.com/roles", Url.new("../roles", base: "https://docs.acme.com/admin/users").to_s
  end

  test "deduplicates on canonical identity" do
    urls = [
      Url.new("https://www.acme.com/pricing"),
      Url.new("https://acme.com/pricing/"),
      Url.new("https://acme.com/pricing?utm_campaign=q4")
    ]

    assert_equal 1, urls.uniq.size
  end

  test "identifies subdomains, ignoring www" do
    assert_equal "docs", Url.new("https://docs.acme.com/x", domain: "acme.com").subdomain
    assert_nil Url.new("https://www.acme.com/x", domain: "acme.com").subdomain
    assert_nil Url.new("https://acme.com/x", domain: "acme.com").subdomain
  end

  test "recognises redundant localized, paginated and archived variants" do
    assert Url.new("https://acme.com/de/pricing").redundant_variant?
    assert Url.new("https://acme.com/blog/page/3").redundant_variant?
    assert Url.new("https://acme.com/blog/2024/03/update").redundant_variant?
    assert Url.new("https://acme.com/blog?page=4").redundant_variant?

    assert_not Url.new("https://acme.com/en/pricing").redundant_variant?
    assert_not Url.new("https://acme.com/pricing").redundant_variant?
    assert_not Url.new("https://acme.com/blog?page=1").redundant_variant?
  end

  test "resolves registrable domains including two-label public suffixes" do
    assert_equal "acme.com", Url.registrable_domain("docs.acme.com")
    assert_equal "acme.co.uk", Url.registrable_domain("help.acme.co.uk")
    assert_equal "acme.test", Url.registrable_domain("acme.test")
  end

  test "resolves whatever a salesperson pastes into a site" do
    site = Url.site("acme.com")

    assert_equal "acme.com", site.domain
    assert_equal "https://acme.com", site.website_url
    assert_equal "Acme", site.name
    assert_nil Url.site("not a url")
  end
end
