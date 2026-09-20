ENV["RAILS_ENV"] ||= "test"
ENV["APP_MODE"] = "fake"
ENV["ENABLE_LIVE_AI"] = "false"

# dotenv loads the developer's .env in the test environment too, so model
# routing is pinned here for the same reason the mode is: a suite that passes
# or fails depending on which provider someone is trying out locally is testing
# their machine rather than the code. Tests that care about routing set it
# themselves with with_env.
ENV["AI_PROVIDER"] = "openai"
ENV["AI_EMBEDDING_MODEL"] = "text-embedding-3-small"
ENV["AI_FAST_MODEL"] = "gpt-5.6-luna"
ENV["AI_ANALYSIS_MODEL"] = "gpt-5.6-terra"
ENV["AI_CHAT_MODEL"] = "gpt-5.6-terra"
ENV.delete("AI_EMBEDDING_PROVIDER")

# dotenv loads the developer's .env in the test environment too, so model
# routing has to be pinned here for the same reason the mode is: a suite that
# passes or fails depending on which provider someone is trying out locally is
# testing their machine rather than the code. Tests that care about routing set
# it themselves with with_env.
ENV["AI_PROVIDER"] = "openai"
ENV["AI_EMBEDDING_MODEL"] = "text-embedding-3-small"
ENV["AI_FAST_MODEL"] = "gpt-5.6-luna"
ENV["AI_ANALYSIS_MODEL"] = "gpt-5.6-terra"
ENV["AI_CHAT_MODEL"] = "gpt-5.6-terra"
ENV.delete("AI_EMBEDDING_PROVIDER")

require_relative "../config/environment"
require "rails/test_help"
require "inertia_rails/minitest"

# After the environment, not before it. dotenv only sets a variable that is not
# already there, so pinning a value above works but deleting one does not --
# booting Rails loads the developer's .env and puts the password straight back,
# and every integration request then answers 401. The suite runs with no
# credentials; the tests that are about the wall set them with with_env.
ENV.delete("FATHOM_USERNAME")
ENV.delete("FATHOM_PASSWORD")

# Same trap, same fix. These are deleted rather than pinned to a value, so the
# copies above the boot are undone by dotenv and the suite ends up testing
# whichever provider and key the developer happens to have in .env.
ENV.delete("AI_EMBEDDING_PROVIDER")
ENV.delete("OPENAI_API_KEY")
ENV.delete("OPENROUTER_API_KEY")

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    fixtures :all

    setup do
      WebsiteIntelligence.reset_configuration!
      NetworkGuard.install!
    end

    teardown do
      NetworkGuard.reset!
    end

    # Builds a lead and scan for the deterministic fixture company.
    def acme_scan
      Scan.start!(Lead.for_website("https://acme.test"))
    end

    # Sets environment variables for the duration of a block and restores
    # exactly what was there before. Tests must not depend on the developer's
    # .env, and must not clobber a credential that is legitimately set.
    def with_env(values)
      original = values.keys.index_with { |key| ENV[key] }
      values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      WebsiteIntelligence.reset_configuration!
      yield
    ensure
      original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      WebsiteIntelligence.reset_configuration!
    end

    # Temporarily replaces a class method. Minitest 6 no longer ships stubbing,
    # and the two places that simulate a provider outage do not justify adding a
    # mocking dependency for it.
    def with_stub(object, name, replacement)
      singleton = object.singleton_class
      original = object.method(name)
      singleton.define_method(name) { |*args, **options, &block| replacement.call(*args, **options, &block) }
      yield
    ensure
      singleton.define_method(name) { |*args, **options, &block| original.call(*args, **options, &block) }
    end

    # A scan crawled, chunked and embedded, but not yet analysed. Enough for
    # anything that needs a real corpus to retrieve from.
    def indexed_acme_scan
      scan = acme_scan
      Website::Map.new(scan).discover!
      CrawlPlan.new(scan).select!

      crawl = Website::Crawl.new(scan)
      crawl.pending.each { |discovered_url| crawl.fetch(discovered_url) }

      index = Corpus::Index.new(scan)
      index.pending_pages.each { |page| index.chunk(page) }
      1.step { break if index.embed_batch.zero? }

      scan.reload
    end

    # Runs the whole pipeline to completion, the way Solid Queue would.
    def run_pipeline(scan, limit: 500)
      perform_enqueued_jobs_until_idle(limit: limit) { StartScanJob.perform_later(scan) }
      scan.reload
    end

    def perform_enqueued_jobs_until_idle(limit:)
      yield if block_given?
      limit.times do
        break if enqueued_jobs.empty?

        perform_enqueued_jobs
      end
    end
  end
end

# Fails loudly on any attempt to open a socket during the test suite.
#
# The promise that CI never spends money is only worth something if something
# enforces it, so this is enforcement rather than documentation: a test that
# reaches for the network fails on the connect, not on the invoice.
module NetworkGuard
  class AttemptedConnection < StandardError; end

  ALLOWED_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

  class << self
    attr_accessor :connections

    def install!
      self.connections = 0
      return if @installed

      TCPSocket.singleton_class.prepend(Module.new do
        def open(host = nil, *args, **options)
          NetworkGuard.check!(host)
          super
        end
      end)

      TCPSocket.prepend(Module.new do
        def initialize(host = nil, *args, **options)
          NetworkGuard.check!(host)
          super
        end
      end)

      @installed = true
    end

    def check!(host)
      return if ALLOWED_HOSTS.include?(host.to_s) || host.to_s.start_with?("127.")

      self.connections = connections.to_i + 1
      raise AttemptedConnection, "Test suite attempted an outbound connection to #{host.inspect}"
    end

    def reset! = self.connections = 0

    def attempted = connections.to_i
  end
end

class ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
end

class ActiveSupport::TestCase
  include ActiveJob::TestHelper
end
