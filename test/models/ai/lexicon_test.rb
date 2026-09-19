require "test_helper"

class AI::LexiconTest < ActiveSupport::TestCase
  test "matches whole words, not substrings" do
    # "subprocessors" contains "sso"; reading that as single sign-on mislabels
    # the evidence and then every finding built on it.
    assert_empty AI::Lexicon.concerns_in("Acme uses a small number of subprocessors.")
    assert_includes AI::Lexicon.concerns_in("Acme supports SAML SSO."), "SSO"

    assert_empty AI::Lexicon.integrations_in("We handle immigration paperwork.")
    assert_includes AI::Lexicon.integrations_in("Syncs to Snowflake nightly."), "Snowflake"
  end

  test "still matches deliberate stems" do
    assert_includes AI::Lexicon.concerns_in("Requests are throttled per workspace."), "rate limits"
    assert_includes AI::Lexicon.concerns_in("Writes are idempotent."), "API reliability"
  end

  test "recognises integration limits, which are never phrased in security terms" do
    assert_includes AI::Lexicon.concerns_in("The connector is one-way only."), "integration limits"
    assert_includes AI::Lexicon.concerns_in("Bidirectional sync is not supported."), "integration limits"
  end

  test "treats acronyms with digits and spaces as whole terms" do
    assert_includes AI::Lexicon.concerns_in("Acme holds SOC 2 Type II."), "SOC 2"
    assert_includes AI::Lexicon.concerns_in("Certified to ISO 27001."), "ISO 27001"
  end
end
