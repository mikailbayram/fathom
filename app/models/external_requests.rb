# frozen_string_literal: true

# The single place that decides whether an outbound provider request is allowed.
#
# Fake mode never degrades into live mode: it raises. That is what makes the
# "zero external calls in CI" guarantee something the test suite can assert on
# rather than something we hope is true.
module ExternalRequests
  def self.allowed? = WebsiteIntelligence.external_requests_allowed?

  def self.guard!(description)
    return true if allowed?

    raise WebsiteIntelligence::ExternalRequestBlocked, <<~MESSAGE.squish
      Blocked an outbound request (#{description}) in #{WebsiteIntelligence.mode} mode.
      Live provider calls require APP_MODE=live and ENABLE_LIVE_AI=true.
    MESSAGE
  end
end
