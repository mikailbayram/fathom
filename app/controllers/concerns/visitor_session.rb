# frozen_string_literal: true

# Who an anonymous demo visitor is, and where that answer is allowed to come
# from.
#
# Three sources, in order: a header the demo sets on every request it makes, the
# token on the URL that loaded it, then the signed cookie. The header is what a
# new endpoint gets for free -- the token used to be threaded onto each URL by
# hand, one was missed, and a widget spent every message talking to a
# conversation nobody was listening to.
#
# Minting is deliberately separate from reading. A page load may create an
# identity; a write may not. A POST that arrives unrecognised is a wiring
# mistake, and quietly starting a fresh conversation for it is how that mistake
# reaches production without appearing in a single log line.
module VisitorSession
  extend ActiveSupport::Concern

  VISITOR_COOKIE = :demo_visitor

  # An embedded widget runs inside a third-party iframe, where the browser sends
  # us no cookie. It therefore mints its own visitor id and tells us -- on the
  # iframe URL for the page load, and in this header for everything after it.
  VISITOR_PARAM = :v
  VISITOR_HEADER = "X-Fathom-Visitor"

  private
    # The visitor this request can prove it is, or nil. Never creates one.
    def visitor_token
      from_header = request.headers[VISITOR_HEADER].to_s
      return from_header if valid_visitor_token?(from_header)

      from_param = params[VISITOR_PARAM].to_s
      return from_param if valid_visitor_token?(from_param)

      cookies.signed[VISITOR_COOKIE].presence
    end

    # A page load may hand out an identity to someone who arrived without one.
    # Nothing else may.
    def establish_visitor!
      existing = visitor_token
      return existing if existing.present?

      cookies.signed[VISITOR_COOKIE] = {
        value: SecureRandom.uuid, expires: 30.days, httponly: true, same_site: :lax
      }
      cookies.signed[VISITOR_COOKIE]
    end

    # A UUID and nothing else, so the parameter cannot be used to smuggle
    # anything into a lookup.
    def valid_visitor_token?(token)
      token.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    # The page load: find this visitor's thread, or start one.
    def conversation_for(chatbot) = Conversation.for_session(chatbot, establish_visitor!)

    # Everything after it. The token is the identity, so a request that carries
    # one gets that thread whether or not it has been seen before -- a widget
    # may legitimately ask its first question with a token it minted itself.
    # What is refused is a request carrying no identity at all, which is not a
    # new visitor but a client that forgot to say who it was.
    def identified_conversation_for(chatbot)
      token = visitor_token
      return nil if token.blank?

      Conversation.for_session(chatbot, token)
    end
end
