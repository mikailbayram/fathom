require "test_helper"

class LeadsTest < ActionDispatch::IntegrationTest
  test "the index leads with the URL form and lists leads" do
    get root_path

    assert_response :success
    assert_inertia_component "Leads/Index"
    assert_equal "fake", inertia.props[:mode]
    assert_empty inertia.props[:leads]
  end

  test "submitting a URL creates the lead and starts its first scan" do
    assert_difference [ -> { Lead.count }, -> { Scan.count } ], 1 do
      assert_enqueued_with(job: StartScanJob) { post leads_path, params: { website_url: "acme.test" } }
    end

    assert_redirected_to lead_path(Lead.last)
    assert_equal "acme.test", Lead.last.domain
  end

  test "scanning the same company twice reuses the lead" do
    post leads_path, params: { website_url: "https://www.acme.test/pricing?utm_source=x" }
    post leads_path, params: { website_url: "acme.test" }

    assert_equal 1, Lead.count
    assert_equal 2, Scan.count
  end

  test "rejects input that is not a website" do
    assert_no_difference -> { Lead.count } do
      post leads_path, params: { website_url: "not a website" }
    end

    assert_redirected_to root_path
  end

  test "a lead with no scan invites one rather than showing an error" do
    lead = Lead.for_website("acme.test")

    get lead_path(lead)

    assert_inertia_component "Leads/Show"
    assert_not inertia.props[:status][:present]
    assert_empty inertia.props[:lead][:findings]
  end

  test "a running scan shows progress on the lead" do
    lead = Lead.for_website("acme.test")
    MapWebsiteJob.perform_now(Scan.start!(lead))

    get lead_path(lead)

    assert inertia.props[:status][:running]
    assert_equal "complete", inertia.props[:status][:steps].first[:state]
  end

  test "the status endpoint is small and pollable" do
    lead = Lead.for_website("acme.test")
    MapWebsiteJob.perform_now(Scan.start!(lead))

    get status_lead_path(lead)

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload["running"]
    assert_equal Scan::Pipeline::STEPS.size, payload["steps"].size
    assert_not payload.key?("findings")
  end

  test "a completed lead carries its gaps, its demo and its plan on one page" do
    lead = Lead.for_website("acme.test")
    run_pipeline(Scan.start!(lead))

    get lead_path(lead)
    props = inertia.props[:lead]

    assert_operator props[:findings].size, :>, 0
    assert_equal props[:findings].map { |f| f[:score] }.sort.reverse, props[:findings].map { |f| f[:score] }
    assert props[:demo][:path].present?
    assert_operator props[:demo][:suggested_questions].size, :>, 0
    assert_operator props[:plan][:selected], :>, 0
    assert_operator props[:metrics][:urls_discovered], :>, 0
  end

  test "rescanning a completed lead starts a new scan rather than editing the old one" do
    lead = Lead.for_website("acme.test")
    run_pipeline(Scan.start!(lead))

    assert_difference -> { lead.scans.count }, 1 do
      assert_enqueued_with(job: StartScanJob) { post rescan_lead_path(lead) }
    end
  end

  test "rescanning a failed scan resumes it in place" do
    lead = Lead.for_website("acme.test")
    scan = Scan.start!(lead)
    scan.fail!(stage: "crawling", error: "upstream refused")

    assert_no_difference -> { lead.scans.count } do
      post rescan_lead_path(lead)
    end

    assert_predicate scan.reload, :pending?
    assert_nil scan.failed_stage
  end

  test "rescan leaves a long-running job alone" do
    lead = Lead.for_website("acme.test")
    scan = Scan.start!(lead)
    scan.claim_stage(:auditing_coverage)
    scan.update_columns(updated_at: 2.hours.ago)
    SolidQueue::Job.enqueue(AuditCoverageJob.new(scan))

    assert_no_enqueued_jobs { post rescan_lead_path(lead) }
    assert_equal "auditing_coverage", scan.reload.status

    get status_lead_path(lead)
    assert_not response.parsed_body["stalled"]
  end

  test "a failed scan names the stage that failed" do
    lead = Lead.for_website("acme.test")
    Scan.start!(lead).fail!(stage: "crawling", error: "Crawler::Client::Error: upstream refused")

    get lead_path(lead)

    assert inertia.props[:status][:failed]
    assert_equal "Reading content", inertia.props[:status][:failed_stage_label]
    assert_match(/upstream refused/, inertia.props[:status][:error_message])
  end

  test "props never leak prompts, model ids or raw analysis" do
    lead = Lead.for_website("acme.test")
    run_pipeline(Scan.start!(lead))

    get lead_path(lead)
    payload = inertia.props.to_json

    assert_not_includes payload, "system_prompt"
    assert_not_includes payload, "raw_analysis"
    assert_not_includes payload, "gpt-5.6"
    assert_not_includes payload, "embedding_model"
    assert_not_includes payload, "content_hash"
  end

  test "a live scan is refused until its credentials are configured" do
    with_env("FIRECRAWL_API_KEY" => nil, "OPENAI_API_KEY" => nil) do
      WebsiteIntelligence.stub_mode(:live) do
        assert_no_difference -> { Scan.count } do
          assert_no_enqueued_jobs { post leads_path, params: { website_url: "acme.test" } }
        end
      end
    end

    assert_redirected_to root_path
  end

  test "a live scan starts once both credentials are configured" do
    with_env("FIRECRAWL_API_KEY" => "fc-key", "OPENAI_API_KEY" => "sk-key") do
      WebsiteIntelligence.stub_mode(:live) do
        assert_difference -> { Scan.count }, 1 do
          assert_enqueued_with(job: StartScanJob) { post leads_path, params: { website_url: "acme.test" } }
        end

        assert_equal "live", Scan.last.mode
      end
    end
  end

  test "a finding detail links back to its lead" do
    lead = Lead.for_website("acme.test")
    scan = Scan.start!(lead)
    run_pipeline(scan)

    get finding_path(scan.findings.viable.ranked.first)

    assert_inertia_component "Findings/Show"
    assert_equal lead.id, inertia.props[:finding][:lead][:id]
    assert inertia.props[:finding][:primary_source][:url].present?
  end
end
