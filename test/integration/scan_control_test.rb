require "test_helper"

class ScanControlTest < ActionDispatch::IntegrationTest
  setup do
    @lead = Lead.for_website("https://acme.test")
    @scan = Scan.start!(@lead)
  end

  test "stopping from the page halts the scan" do
    @scan.claim_stage(:crawling)

    post stop_lead_path(@lead)

    assert_redirected_to lead_path(@lead)
    assert_predicate @scan.reload, :stopped?
  end

  test "stopping a lead with nothing running is harmless" do
    @scan.complete!

    post stop_lead_path(@lead)

    assert_redirected_to lead_path(@lead)
    assert_predicate @scan.reload, :completed?
  end

  test "deleting removes the scan and leaves the lead" do
    delete scan_lead_path(@lead)

    assert_redirected_to lead_path(@lead)
    assert_nil Scan.find_by(id: @scan.id)
    assert Lead.exists?(@lead.id)
  end

  test "deleting a running scan stops it on the way out" do
    @scan.claim_stage(:crawling)

    assert_difference -> { Scan.count }, -1 do
      delete scan_lead_path(@lead)
    end
  end

  test "the page says a scan was stopped rather than failed" do
    @scan.claim_stage(:crawling)
    @scan.stop!

    get lead_path(@lead)

    assert_response :success
    assert_equal "stopped", inertia.props[:lead][:status]
    assert_equal false, inertia.props[:lead][:failed]
    assert_equal false, inertia.props[:lead][:running]
  end
end
