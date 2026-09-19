module ApplicationCable
  # Public demo visitors are anonymous. The only thing a connection is allowed
  # to claim is the signed visitor cookie it already carries, which is what
  # scopes it to its own conversation and nobody else's.
  class Connection < ActionCable::Connection::Base
    identified_by :visitor_id

    def connect
      # Same reason the controller accepts one: an embedded widget is a
      # third-party iframe and gets no cookie.
      from_param = request.params[VisitorSession::VISITOR_PARAM].to_s
      self.visitor_id = uuid?(from_param) ? from_param : cookies.signed[VisitorSession::VISITOR_COOKIE]
      reject_unauthorized_connection if visitor_id.blank?
    end

    private
      def uuid?(token)
        token.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end
  end
end
