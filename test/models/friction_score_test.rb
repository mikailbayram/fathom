require "test_helper"

class FrictionScoreTest < ActiveSupport::TestCase
  setup { @scan = acme_scan }

  test "scores a buried, high-importance, well-evidenced answer highly" do
    finding = build_finding(importance: 0.95, full: 0.97, buyer_visible: 0.1, page_type: "docs")

    assert_operator FrictionScore.new(finding).points, :>=, 80
    assert_predicate FrictionScore.new(finding), :viable?
  end

  test "penalises an answer the buyer-visible site already gives" do
    buried = build_finding(importance: 0.9, full: 0.95, buyer_visible: 0.1, page_type: "docs")
    prominent = build_finding(importance: 0.9, full: 0.95, buyer_visible: 0.9, page_type: "pricing",
                              buyer_visible_answer: "SAML SSO is included on the Business plan.")

    assert_operator FrictionScore.new(prominent).points, :<, FrictionScore.new(buried).points
    assert_equal(-FrictionScore::PROMINENTLY_AVAILABLE_PENALTY,
                 FrictionScore.new(prominent).breakdown["prominently_available_penalty"])
  end

  test "rewards obscurity by the kind of page the answer came from" do
    scores = %w[pdf developer_docs docs help_center pricing homepage].map do |page_type|
      FrictionScore.new(build_finding(page_type: page_type)).points
    end

    assert_equal scores, scores.sort.reverse, "more buried sources should score higher"
  end

  test "rewards technically specific questions" do
    specific = build_finding(question: "What are Acme's documented RPO and RTO for a regional outage?",
                             answer: "The RPO is 15 minutes and the RTO is 4 hours on the Enterprise plan.")
    vague = build_finding(question: "Is Acme any good?", answer: "Acme is a platform.")

    assert_operator FrictionScore.new(specific).breakdown["specificity"],
                    :>,
                    FrictionScore.new(vague).breakdown["specificity"]
  end

  test "never exceeds one hundred or falls below zero" do
    best = build_finding(importance: 1.0, full: 1.0, buyer_visible: 0.0, page_type: "pdf",
                         question: "What are the RPO, RTO, SLA and SOC 2 commitments?",
                         answer: "RPO 15 minutes, RTO 4 hours, on the Enterprise plan.")
    worst = build_finding(importance: 0.0, full: 0.0, buyer_visible: 1.0, page_type: "homepage",
                          answer: nil, buyer_visible_answer: "Yes.")

    assert_operator FrictionScore.new(best).points, :<=, 100
    assert_operator FrictionScore.new(worst).points, :>=, 0
  end

  test "marks a claim with no supported statement as covered rather than scoring it" do
    score = FrictionScore.new(build_finding(answer: nil, full: 0.0))

    assert_equal "covered", score.status
    assert_not score.viable?
  end

  test "marks a weakly evidenced answer below threshold" do
    score = FrictionScore.new(build_finding(importance: 0.2, full: 0.5, buyer_visible: 0.4, page_type: "marketing"))

    assert_equal "below_threshold", score.status
  end

  test "measures the gap as how much of a published fact a buyer can reach" do
    score = FrictionScore.new(build_finding(full: 0.8, buyer_visible: 0.1))

    assert_in_delta 0.9, score.gap, 0.0001
    assert_equal 36, score.breakdown["discoverability_gap"]
    assert_equal 90.0, score.to_attributes[:discoverability_score]
  end

  test "reports almost no gap when the buyer-visible site states it plainly" do
    assert_in_delta 0.05, FrictionScore.new(build_finding(full: 0.8, buyer_visible: 0.95)).gap, 0.0001
  end

  test "publishes every component so the number can be explained" do
    breakdown = FrictionScore.new(build_finding).breakdown

    assert_equal FrictionScore::WEIGHTS.keys.map(&:to_s).sort,
                 (breakdown.keys & FrictionScore::WEIGHTS.keys.map(&:to_s)).sort
    assert breakdown.key?("total")
    assert breakdown.key?("source_type")
  end

  private
    def build_finding(importance: 0.8, full: 0.9, buyer_visible: 0.1, page_type: "docs",
                      question: "Can administrators define custom RBAC roles?",
                      answer: "Custom roles with granular permissions are available on the Enterprise plan.",
                      buyer_visible_answer: nil)
      record = @scan.claims.create!(question_text: question, statement: "#{answer.presence || question} (#{SecureRandom.hex(3)})",
                                    category: "security_compliance", buyer_importance: importance,
                                    support: full, topic: "RBAC")
      finding = record.create_finding!(
        scan: @scan, answer: answer, buyer_visible_answer: buyer_visible_answer,
        answer_confidence: full, buyer_importance: importance,
        full_corpus_confidence: full, buyer_visible_confidence: buyer_visible, status: "pending"
      )
      finding.finding_sources.create!(chunk: chunk_for(page_type), relevance_score: 1.0, is_primary: true)
      finding
    end

    def chunk_for(page_type)
      @chunks ||= {}
      @chunks[page_type] ||= begin
        url = "https://acme.test/#{page_type}-#{SecureRandom.hex(4)}"
        discovered = @scan.discovered_urls.create!(
          url: url, canonical_url: url, host: "acme.test", path: "/#{page_type}",
          source: "sitemap", page_type: page_type, corpus_type: PageTypes.corpus_for(page_type), priority: 50
        )
        page = @scan.pages.create!(
          discovered_url: discovered, url: url, canonical_url: url, title: page_type.humanize,
          page_type: page_type, corpus_type: PageTypes.corpus_for(page_type),
          content: "evidence", content_hash: Digest::SHA256.hexdigest(url)
        )
        page.chunks.create!(scan: @scan, corpus_type: page.corpus_type, content: "evidence", position: 0,
                            metadata: { "page_type" => page_type, "url" => url })
      end
    end
end
