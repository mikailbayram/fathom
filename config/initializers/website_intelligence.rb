# frozen_string_literal: true

# Defaults and their reasoning live in WebsiteIntelligence::Configuration, which
# reads the same environment variables. Override them here only to change what a
# deployment does differently from the default -- a value restated with the same
# literal is a second place to keep in step, and this file is the one that wins.

# RubyLLM is only wired up when live spending has been explicitly enabled. In
# fake and local mode the application never constructs a live provider, so a
# stray API key in the environment cannot cause a paid request.
if WebsiteIntelligence.live_ai_enabled?
  RubyLLM.configure do |config|
    WebsiteIntelligence.ai_credentials.each { |setting, key| config.public_send(:"#{setting}=", key) }
  end
end
