# frozen_string_literal: true

module Fathom
  # The shared password in front of the internal application.
  #
  # Credentials come from the environment, and when none are set the app is
  # closed rather than open: an unconfigured deployment that quietly served
  # every prospect's scan to the internet would be a worse failure than one that
  # refuses to serve anybody. The single exception is a request from the machine
  # Rails is running on in development, so a developer who has not set anything
  # can still work.
  module BasicAuth
    USERNAME_VAR = "FATHOM_USERNAME"
    PASSWORD_VAR = "FATHOM_PASSWORD"

    # Action Cable authenticates on the WebSocket handshake, where Basic
    # credentials are not reliably re-sent by the browser. So passing the
    # password sets this signed cookie, and the socket reads that instead.
    OPERATOR_COOKIE = :fathom_operator

    class << self
      def credentials
        username = ENV[USERNAME_VAR].to_s
        password = ENV[PASSWORD_VAR].to_s
        return nil if username.empty? || password.empty?

        [ username, password ]
      end

      def configured? = !credentials.nil?

      # Only when nothing is configured, and only for a request from the
      # machine Rails is running on in development or test. Credentials that
      # exist are always enforced, including locally -- an exception that
      # outranks a configured password is not a password.
      def optional?(request)
        !configured? && Rails.env.local? && request.local?
      end

      def valid?(username, password)
        expected = credentials
        return false if expected.nil?

        # Both comparisons always run: returning early on the username would
        # leak which half was wrong through how long the answer took.
        matches = secure_compare(username, expected.first)
        matches & secure_compare(password, expected.last)
      end

      private
        def secure_compare(given, expected)
          ActiveSupport::SecurityUtils.secure_compare(given.to_s, expected)
        end
    end
  end
end
