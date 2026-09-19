require "test_helper"

class ScanChannelTest < ActionCable::Channel::TestCase
  include ActionCable::TestHelper

  setup do
    @scan = Scan.start!(Lead.for_website("https://acme.test"))
    stub_connection(visitor_id: SecureRandom.uuid, operator: true)
  end

  test "streams one lead's progress to anyone watching that lead" do
    subscribe(lead_id: @scan.lead_id)

    assert_predicate subscription, :confirmed?
    assert_has_stream_for @scan.lead
  end

  test "streams the list to a subscriber that names no lead" do
    subscribe

    assert_predicate subscription, :confirmed?
    assert_has_stream ScanChannel::LIST_STREAM
  end

  test "refuses a demo visitor, who has a valid connection and no business here" do
    stub_connection(visitor_id: SecureRandom.uuid, operator: false)
    subscribe(lead_id: @scan.lead_id)

    assert_predicate subscription, :rejected?

    subscribe
    assert_predicate subscription, :rejected?
  end

  test "rejects a subscription to a lead that does not exist" do
    subscribe(lead_id: 0)

    assert_predicate subscription, :rejected?
  end

  test "claiming a stage tells both the lead's page and the list" do
    assert_broadcasts(ScanChannel::LIST_STREAM, 1) do
      assert_broadcasts(ScanChannel.broadcasting_for(@scan.lead), 1) do
        @scan.claim_stage(:mapping)
      end
    end
  end

  test "claiming a stage already claimed says nothing" do
    @scan.claim_stage(:mapping)

    assert_no_broadcasts(ScanChannel::LIST_STREAM) do
      assert_not @scan.claim_stage(:mapping)
    end
  end

  test "finishing and failing are broadcast like any other change" do
    assert_broadcasts(ScanChannel::LIST_STREAM, 1) { @scan.complete! }
    assert_broadcasts(ScanChannel::LIST_STREAM, 1) { @scan.fail!(stage: "mapping", error: "boom") }
  end

  test "counters moving inside a stage are broadcast too" do
    scan = indexed_acme_scan

    assert_broadcasts(ScanChannel::LIST_STREAM, 1) { scan.broadcast_status! }
  end

  test "the payload carries what the page renders from" do
    @scan.claim_stage(:crawling)
    payload = broadcasts(ScanChannel.broadcasting_for(@scan.lead)).last.then { |message| JSON.parse(message) }

    assert_equal "crawling", payload["status"]
    assert_equal "Reading content", payload["stage_label"], "the row has to be able to name the stage"
    assert_equal false, payload["waiting_for_slot"]
    assert payload["metrics"].key?("cost"), "the page shows the cost while the scan runs"
    assert_equal 12, payload["steps"].size
  end

  test "a broadcast that blows up does not take the scan down with it" do
    with_stub(ScanChannel, :broadcast_status, ->(_scan) { raise "cable is down" }) do
      assert @scan.claim_stage(:planning)
    end

    assert_equal "planning", @scan.reload.status
  end

  test "nothing is broadcast until the transaction that changed it commits" do
    broadcasts = 0

    ActiveRecord::Base.transaction do
      with_stub(ScanChannel, :broadcast_status, ->(_scan) { broadcasts += 1 }) do
        @scan.claim_stage(:mapping)
        assert_equal 0, broadcasts, "a stage that might roll back must not be announced"
      end
    end
  end
end
