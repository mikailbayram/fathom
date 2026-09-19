require "test_helper"

class Website::MapTest < ActiveSupport::TestCase
  setup { @scan = acme_scan }

  test "records every discovered URL before anything is fetched" do
    Website::Map.new(@scan).discover!

    assert_operator @scan.discovered_urls.count, :>, 15
    assert_equal @scan.discovered_urls.count, @scan.reload.urls_discovered
    assert_equal 0, @scan.pages.count, "mapping must not fetch anything"
  end

  test "deduplicates a URL reached from several sources" do
    Website::Map.new(@scan).discover!

    canonicals = @scan.discovered_urls.pluck(:canonical_url)
    assert_equal canonicals.uniq.size, canonicals.size
  end

  test "records where each URL came from" do
    Website::Map.new(@scan).discover!
    sources = @scan.discovered_urls.distinct.pluck(:source)

    assert_includes sources, "root"
    assert_includes sources, "sitemap"
    assert_includes sources, "subdomain"
    # The enterprise guide is linked from the homepage but absent from the
    # sitemap, which is exactly how a buried PDF behaves in the wild.
    assert_includes sources, "pdf_link"
  end

  test "discovers the relevant public subdomains" do
    Website::Map.new(@scan).discover!
    hosts = @scan.discovered_urls.distinct.pluck(:host)

    assert_includes hosts, "docs.acme.test"
    assert_includes hosts, "developers.acme.test"
    assert_includes hosts, "help.acme.test"
    assert_includes hosts, "trust.acme.test"
  end

  test "classifies discovered URLs into corpora as it records them" do
    Website::Map.new(@scan).discover!

    assert @scan.discovered_urls.exists?(canonical_url: "https://docs.acme.test/roles", corpus_type: CorpusTypes::DEEP)
    assert @scan.discovered_urls.exists?(canonical_url: "https://acme.test/pricing", corpus_type: CorpusTypes::BUYER_VISIBLE)
  end

  test "flags redundant variants rather than dropping them" do
    Website::Map.new(@scan).discover!
    localized = @scan.discovered_urls.find_by(canonical_url: "https://acme.test/de/pricing")

    assert localized, "the variant is still recorded, so the plan can explain itself"
    assert_equal true, localized.metadata["redundant_variant"]
  end

  test "excludes URLs outside the lead's domain" do
    Website::Map.new(@scan).discover!
    hosts = @scan.discovered_urls.pluck(:host)

    assert_predicate hosts, :any?
    assert_empty hosts.reject { |host| host.end_with?("acme.test") }
  end

  test "is idempotent" do
    Website::Map.new(@scan).discover!
    first = @scan.discovered_urls.count

    Website::Map.new(@scan).discover!

    assert_equal first, @scan.reload.discovered_urls.count
  end

  test "respects the configured discovery ceiling" do
    WebsiteIntelligence.config.max_discovered_urls = 5
    Website::Map.new(@scan).discover!

    assert_equal 5, @scan.discovered_urls.count
  ensure
    WebsiteIntelligence.reset_configuration!
  end
end
