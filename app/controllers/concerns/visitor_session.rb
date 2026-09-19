# frozen_string_literal: true

# The signed cookie that identifies an anonymous demo visitor.
#
# It has to exist before the page renders, not merely before the first message:
# the Action Cable connection authenticates with it on subscribe, and a
# subscription rejected at mount never retries, so the reply is generated and
# then delivered to nobody.
module VisitorSession
  extend ActiveSupport::Concern

  VISITOR_COOKIE = :demo_visitor

  VISITOR_PARAM = :v

  private
    # An embedded widget runs this page inside an iframe on another origin,
    # where the browser will not send our cookie. The widget therefore mints its
    # own visitor id and passes it along; it identifies an anonymous demo
    # thread and nothing else.
    def visitor_id
      from_param = params[VISITOR_PARAM].to_s
      return from_param if valid_visitor_token?(from_param)

      cookies.signed[VISITOR_COOKIE] ||= {
        value: SecureRandom.uuid, expires: 30.days, httponly: true, same_site: :lax
      }
      cookies.signed[VISITOR_COOKIE]
    end

    # A UUID and nothing else, so the parameter cannot be used to smuggle
    # anything into a lookup.
    def valid_visitor_token?(token)
      token.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    def conversation_for(chatbot) = Conversation.for_session(chatbot, visitor_id)
end
