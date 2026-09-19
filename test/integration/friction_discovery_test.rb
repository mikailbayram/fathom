require "test_helper"

# The definition of done (spec §59).
#
# Given a company whose buyer-visible site says only "enterprise-grade access
# controls" while its documentation states plainly that custom RBAC roles are an
# Enterprise-plan capability, the whole product has to notice, rank it, evidence
# it, and be able to talk about it -- without one external HTTP request.
class FrictionDiscoveryTest < ActionDispatch::IntegrationTest
  RBAC_QUESTION = /custom RBAC roles/i

  setup do
    @scan = acme_scan
    run_pipeline(@scan)
    @finding = @scan.findings.viable.ranked.detect { |finding| finding.claim.statement.match?(RBAC_QUESTION) }
  end

  test "the scan completes every stage" do
    assert_predicate @scan, :completed?
    assert_nil @scan.failed_stage
    assert_predicate @scan.pipeline, :complete?
  end

  test "mapping precedes crawling and selects a subset" do
    assert_operator @scan.urls_discovered, :>, @scan.pages_selected
    assert_operator @scan.pages_selected, :>, 0
    assert_equal @scan.pages_selected, @scan.discovered_urls.selected.count
  end

  test "the corpus is split into buyer-visible and deep content" do
    corpora = @scan.chunks.distinct.pluck(:corpus_type)

    assert_includes corpora, CorpusTypes::BUYER_VISIBLE
    assert_includes corpora, CorpusTypes::DEEP
  end

  test "the company is understood from its own content" do
    profile = @scan.company_profile

    assert_equal "Acme", profile.company_name
    assert_includes profile.named_integrations, "NetSuite"
    assert_includes profile.concerns, "RBAC"
  end

  test "claims come from what the company published, not from a fixed list" do
    # Coverage-audit claims stand for an absence, so they have no passage.
    claims = @scan.claims.where.not(support: 0.0)

    assert_operator claims.count, :>, 5
    assert_operator claims.distinct.count(:category), :>=, 4

    claims.each do |claim|
      assert claim.chunk_id.present?, "every claim cites the passage it came from"
      assert_equal CorpusTypes::DEEP, claim.chunk.corpus_type
      assert_operator claim.support, :>=, Claim::MINIMUM_SUPPORT
    end

    # Nothing in a template bank would have produced this one.
    assert claims.any? { |claim| claim.statement.match?(/NetSuite integration is one-way only/i) }
  end

  test "the RBAC fact is quoted from what the company published" do
    assert @finding, "the custom RBAC finding should exist"
    assert_operator @finding.full_corpus_confidence, :>=, Claim::MINIMUM_SUPPORT
    assert_match(/Enterprise plan/i, @finding.answer)
    assert_equal @finding.claim.statement, @finding.answer
  end

  test "the RBAC fact is not reachable from the buyer-visible corpus" do
    assert_nil @finding.buyer_visible_answer
    assert_operator @finding.buyer_visible_confidence, :<, 0.3
  end

  test "the gap between the two corpora is large" do
    assert_operator @finding.discoverability_gap_points, :>=, 50
  end

  test "a high value finding is created and ranked" do
    assert_predicate @finding, :viable?
    assert_operator @finding.friction_score, :>=, WebsiteIntelligence.config.minimum_finding_score
    assert_equal @scan.findings.viable.ranked.map(&:friction_score).sort.reverse,
                 @scan.findings.viable.ranked.map(&:friction_score)
  end

  test "the technical source is attached as evidence" do
    source = @finding.primary_source

    assert source, "a viable finding must carry its evidence"
    assert_equal "https://docs.acme.test/roles", source.source_url
    assert_equal "docs", source.page_type
    assert_equal CorpusTypes::DEEP, source.corpus_type
    assert source.quoted_excerpt.present?
    assert_equal "deep", @finding.source_depth
  end

  test "a claim the buyer-visible site already makes is not an opportunity" do
    covered = @scan.findings.where.not(buyer_visible_answer: nil)

    assert_predicate covered, :any?, "the pricing page states some of what the docs state"
    covered.each do |finding|
      assert_not finding.viable?, "a fact a buyer can already read is not a gap: #{finding.claim.statement}"
    end
  end

  test "topics the company answers nowhere are reported as their own kind of gap" do
    missing = @scan.findings.where(kind: "missing")

    assert_predicate missing, :any?, "a scan should say what a buyer will ask and never find"
    missing.each do |finding|
      assert_nil finding.answer, "nothing was published, so there is nothing to quote"
      assert_empty finding.finding_sources, "an absence has no source"
      assert finding.topic.present?
      assert_operator finding.buyer_importance, :>, 0.5
    end
  end

  test "a chatbot is created for the completed scan" do
    assert @scan.chatbot.present?
    assert_predicate @scan.chatbot, :publicly_shared?
  end

  test "the finding appears as a suggested chatbot question" do
    assert_includes @scan.chatbot.suggested_questions(limit: 10), @finding.claim.question_text
  end

  test "asking the chatbot the RBAC question returns the grounded answer with its source" do
    get public_demo_path(@scan.chatbot.slug)
    post public_demo_messages_path(@scan.chatbot.slug), params: { question: @finding.claim.question_text }
    perform_enqueued_jobs

    answer = @scan.chatbot.conversations.first.messages.where(role: "assistant").last

    assert answer.grounded?
    assert_match(/custom RBAC roles/i, answer.content)
    assert_match(/Enterprise plan/i, answer.content)
    assert_equal "https://docs.acme.test/roles", answer.sources.first["url"]
  end

  test "the salesperson can walk the whole workflow through the UI" do
    post leads_path, params: { website_url: "https://acme.test" }
    lead = Lead.order(:created_at).last
    assert_redirected_to lead_path(lead)

    perform_enqueued_jobs_until_idle(limit: 500)

    # The gaps, the evidence and the demo are all reachable from the one page
    # that represents this company.
    get lead_path(lead)
    assert_inertia_component "Leads/Show"
    assert_operator inertia.props[:lead][:findings].size, :>, 0

    demo_path = inertia.props[:lead][:demo][:path]
    finding_id = inertia.props[:lead][:findings].first[:id]

    get finding_path(finding_id)
    assert_inertia_component "Findings/Show"
    assert inertia.props[:finding][:primary_source][:url].present?
    assert_equal lead.id, inertia.props[:finding][:lead][:id]

    get demo_path
    assert_inertia_component "Demos/Show"
  end

  test "zero external HTTP requests were made" do
    assert_equal 0, NetworkGuard.attempted
    assert_equal [ "fake" ], AIUsage.where(scan: @scan).distinct.pluck(:provider)
    assert_equal 0, AIUsage.where(scan: @scan).sum(:estimated_cost)
  end
end
