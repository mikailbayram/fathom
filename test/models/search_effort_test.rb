require "test_helper"

class SearchEffortTest < ActiveSupport::TestCase
  setup { @scan = acme_scan }

  test "an answer the buyer-visible pages half-state is signposted, wherever it lives" do
    band = SearchEffort.derive(page: page_for("pdf", host: "acme.test"), coverage: 0.6, domain: "acme.test")

    assert_equal "signposted", band
  end

  test "a PDF nothing on the journey mentions is a dead end" do
    band = SearchEffort.derive(page: page_for("pdf"), coverage: 0.0, domain: "acme.test")

    assert_equal "dead_end", band
  end

  test "documentation on a separate subdomain is a long hunt once something hints at it" do
    band = SearchEffort.derive(page: page_for("docs", host: "docs.acme.test"), coverage: 0.2, domain: "acme.test")

    assert_equal "long_hunt", band
  end

  test "documentation on the main domain is a short hunt" do
    band = SearchEffort.derive(page: page_for("docs"), coverage: 0.2, domain: "acme.test")

    assert_equal "short_hunt", band
  end

  test "a claim published nowhere is a dead end" do
    assert_equal "dead_end", SearchEffort.derive(page: nil, coverage: 0.0, domain: "acme.test")
  end

  test "every band carries a label, a short label and a meaning" do
    SearchEffort::ALL.each do |band|
      assert SearchEffort.label(band).present?, band
      assert SearchEffort.short_label(band).present?, band
      assert SearchEffort.meaning(band).present?, band
    end
  end

  test "an unknown band falls back rather than blanking the badge" do
    assert_equal SearchEffort.label(SearchEffort::DEFAULT), SearchEffort.label("nonsense")
    assert_not SearchEffort.valid?("nonsense")
  end

  test "the bands are ordered by how long the hunt takes" do
    durations = %w[signposted short_hunt long_hunt].map { |band| SearchEffort.seconds(band) }

    assert_equal durations, durations.sort
    assert_nil SearchEffort.seconds("dead_end"), "a dead end has no duration"
  end

  test "a finding reports the band the check recorded" do
    finding = build_finding(search_effort: "long_hunt")

    assert_equal "long_hunt", finding.search_effort_band
    assert_equal SearchEffort.label("long_hunt"), finding.search_effort_label
  end

  test "a finding scored before any model was asked still reports a band" do
    finding = build_finding(search_effort: nil, page_type: "pdf", buyer_visible: 0.0)

    assert_equal "dead_end", finding.search_effort_band
  end

  test "a question the company answered nowhere is always a dead end" do
    finding = build_finding(kind: "missing", search_effort: "signposted")

    assert_equal "dead_end", finding.search_effort_band
  end

  test "the fake answerer records a band and a sentence for every claim" do
    scan = indexed_acme_scan
    answer = AI::Answerer.build(scan).answer("Acme retains customer data for 30 days.",
                                             scope: :buyer_visible, destination: scan.pages.first)

    assert SearchEffort.valid?(answer.search_effort), answer.search_effort
    assert answer.search_path.present?
  end

  private
    def build_finding(page_type: "docs", buyer_visible: 0.1, kind: "buried", search_effort: nil)
      claim = @scan.claims.create!(
        question_text: "Can administrators define custom RBAC roles?",
        statement: "Custom roles are available on the Enterprise plan. (#{SecureRandom.hex(3)})",
        category: "security_compliance", buyer_importance: 0.8, support: 0.9, topic: "RBAC"
      )
      finding = claim.create_finding!(
        scan: @scan, kind: kind, answer: "Custom roles are available on the Enterprise plan.",
        answer_confidence: 0.9, buyer_importance: 0.8, full_corpus_confidence: 0.9,
        buyer_visible_confidence: buyer_visible, search_effort: search_effort, status: "pending"
      )
      page = page_for(page_type)
      chunk = page.chunks.create!(scan: @scan, corpus_type: page.corpus_type, content: "evidence",
                                  position: 0, token_count: 120,
                                  metadata: { "page_type" => page_type, "url" => page.url })
      finding.finding_sources.create!(chunk: chunk, relevance_score: 1.0, is_primary: true)
      finding
    end

    def page_for(page_type, host: "acme.test")
      url = "https://#{host}/#{page_type}-#{SecureRandom.hex(4)}"
      discovered = @scan.discovered_urls.create!(
        url: url, canonical_url: url, host: host, path: "/#{page_type}", source: "sitemap",
        page_type: page_type, corpus_type: PageTypes.corpus_for(page_type), priority: 50
      )
      @scan.pages.create!(
        discovered_url: discovered, url: url, canonical_url: url, title: page_type.humanize,
        page_type: page_type, corpus_type: PageTypes.corpus_for(page_type), word_count: 900,
        content: "evidence", content_hash: Digest::SHA256.hexdigest(url)
      )
    end
end
