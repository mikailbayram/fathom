class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import
  # maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # The whole internal application sits behind one shared password. It is HTTP
  # Basic because that is the least machinery that actually keeps strangers out:
  # no accounts, no sessions, no password reset, nothing to maintain. The one
  # exception is the public demo, which is the surface this product exists to
  # share, and which opts out explicitly.
  before_action :authenticate_operator

  inertia_share flash: -> { flash.to_hash }

  private
    def authenticate_operator
      return if Fathom::BasicAuth.optional?(request)

      authenticated = authenticate_or_request_with_http_basic("Fathom") do |username, password|
        Fathom::BasicAuth.valid?(username, password)
      end
      mark_operator if authenticated
    end

    # The socket cannot ask for a password, so it trusts this instead.
    def mark_operator
      cookies.signed[Fathom::BasicAuth::OPERATOR_COOKIE] = {
        value: true, expires: 12.hours, httponly: true, same_site: :lax
      }
    end
end
