# frozen_string_literal: true

namespace :app do
  desc "Report whether this environment is ready, and what it is allowed to spend"
  task doctor: :environment do
    Doctor.new.report
  end
end

# Answers two questions a developer actually has: can I run this, and can it
# spend my money? Everything it prints is checked, never assumed.
class Doctor
  PASS = "✓"
  FAIL = "✗"
  NEUTRAL = "○"
  RULE = "─" * 40

  def report
    heading
    application
    infrastructure
    integrations
    verdict
  end

  private
    def heading
      puts "\nWebsite Friction Intelligence"
      puts RULE
    end

    def application
      mode = WebsiteIntelligence.mode

      section "Application mode", state(mode == :fake ? :pass : :neutral), mode.to_s.upcase
      section "External requests", state(ExternalRequests.allowed? ? :neutral : :pass),
              ExternalRequests.allowed? ? "ENABLED" : "DISABLED"
      section "AI token spending", spending_state, spending_label
      section "Crawler spending", spending_state, spending_label
    end

    def infrastructure
      puts
      check("PostgreSQL") { ActiveRecord::Base.connection.execute("SELECT 1") && "Connected" }
      check("pgvector") { vector_version }
      check("Solid Queue") { solid_queue_state }
      check("Embedding column") { embedding_column }
    end

    def integrations
      puts "\nLive integrations"
      puts RULE

      credential("OPENAI_API_KEY", "embeddings + AI analysis")
      credential("FIRECRAWL_API_KEY", "mapping/crawling public websites")
    end

    def verdict
      puts
      if failures.empty? && (!WebsiteIntelligence.live? || missing_credentials.empty?)
        puts WebsiteIntelligence.live? ? "Ready for a live scan." : "Everything required for development is ready."
      elsif failures.any?
        puts "#{FAIL} Not ready: #{failures.join(', ')}."
        exit 1
      else
        puts "#{FAIL} Live mode is selected but #{missing_credentials.join(' and ')} #{missing_credentials.one? ? 'is' : 'are'} missing."
        puts "  A live scan cannot start until they are configured."
        exit 1
      end
    end

    def section(label, symbol, value)
      puts "\n#{label}"
      puts "#{symbol} #{value}"
    end

    def check(label)
      puts "\n#{label}"
      puts "#{PASS} #{yield}"
    rescue StandardError => error
      failures << label
      puts "#{FAIL} #{error.message.lines.first.to_s.strip}"
    end

    def credential(name, purpose)
      configured = ENV[name].present?
      required = WebsiteIntelligence.live?

      puts
      puts "#{configured ? PASS : NEUTRAL} #{name}"
      puts "  #{configured ? 'Configured' : 'Not configured'}"
      puts "  Purpose: #{purpose}"

      if configured
        puts "  Value is never printed, logged or committed"
      elsif required
        missing_credentials << name
        puts "  REQUIRED in live mode"
      else
        puts "  Not required in #{WebsiteIntelligence.mode} mode"
      end
    end

    def state(result) = result == :pass ? PASS : NEUTRAL

    def spending_state = WebsiteIntelligence.live_ai_enabled? ? NEUTRAL : PASS

    def spending_label
      return "DISABLED" unless WebsiteIntelligence.live_ai_enabled?

      format("ENABLED (max $%.2f per scan, $%.2f per day)",
             WebsiteIntelligence.max_scan_ai_cost_usd, WebsiteIntelligence.max_daily_ai_cost_usd)
    end

    def vector_version
      version = ActiveRecord::Base.connection.select_value("SELECT extversion FROM pg_extension WHERE extname = 'vector'")
      raise "pgvector extension is not installed in this database" if version.blank?

      "Available (#{version})"
    end

    def solid_queue_state
      ready = SolidQueue::Job.where(finished_at: nil).count
      workers = SolidQueue::Process.where(kind: "Worker").count

      raise "Schema missing. Run bin/rails db:prepare" unless SolidQueue::Job.table_exists?

      workers.positive? ? "Running (#{workers} worker#{'s' if workers != 1}, #{ready} queued)" : "Schema ready (no worker running; start bin/jobs)"
    end

    def embedding_column
      expected = WebsiteIntelligence.config.ai.embedding_dimensions
      actual = ActiveRecord::Base.connection.select_value(<<~SQL)
        SELECT atttypmod FROM pg_attribute
        WHERE attrelid = 'chunks'::regclass AND attname = 'embedding'
      SQL

      raise "chunks.embedding is missing. Run bin/rails db:migrate" if actual.nil?
      if actual.to_i != expected
        raise "chunks.embedding is vector(#{actual}) but #{WebsiteIntelligence.config.ai.embedding_model} needs vector(#{expected})"
      end

      "vector(#{expected}) matches #{WebsiteIntelligence.config.ai.embedding_model}"
    end

    def failures = @failures ||= []

    def missing_credentials = @missing_credentials ||= []
end
