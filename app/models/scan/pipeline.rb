# frozen_string_literal: true

class Scan
  # Walks a scan through the pipeline using the database as the source of truth.
  #
  #   scan.pipeline.advance!
  #
  # No job knows what comes after it. Each one does its work, records the result,
  # and asks the pipeline what is left -- so a retried job, a resumed scan and a
  # rerun of the whole thing all take the same path, and nothing depends on a
  # timer or on jobs arriving in order.
  class Pipeline
    Step = Data.define(:stage, :job, :complete) do
      def complete?(facts) = complete.call(facts)
      def job_class = job.constantize
    end

    # One snapshot of everything the ten steps need to know, gathered in a
    # handful of queries. Asking each step to work it out for itself cost
    # twenty-two queries per call, which the progress screen then made every
    # second and a half.
    Facts = Data.define(
      :discovered, :planned, :uncrawled, :unchunked, :unembedded, :profiled,
      :claims_extracted, :unresolved_claims, :unscored_findings, :chatbot,
      :pages_crawled, :pages_selected, :pages_indexed, :chunks, :claims_total,
      :claims_checked, :findings, :urls_discovered, :classified, :refined, :category, :coverage_audited
    )

    STEPS = [
      Step.new(stage: "mapping", job: "MapWebsiteJob",
               complete: ->(facts) { facts.discovered }),
      Step.new(stage: "classifying", job: "ClassifyUrlsJob",
               complete: ->(facts) { facts.classified }),
      Step.new(stage: "planning", job: "BuildCrawlPlanJob",
               complete: ->(facts) { facts.planned }),
      Step.new(stage: "crawling", job: "CrawlPagesJob",
               complete: ->(facts) { facts.uncrawled.zero? }),
      Step.new(stage: "processing", job: "ProcessPagesJob",
               complete: ->(facts) { facts.unchunked.zero? }),
      Step.new(stage: "embedding", job: "EmbedChunksJob",
               complete: ->(facts) { facts.unembedded.zero? }),
      Step.new(stage: "analyzing", job: "AnalyzeCompanyJob",
               complete: ->(facts) { facts.profiled }),
      Step.new(stage: "extracting_claims", job: "ExtractClaimsJob",
               complete: ->(facts) { facts.claims_extracted }),
      Step.new(stage: "checking_visibility", job: "CheckVisibilityJob",
               complete: ->(facts) { facts.unresolved_claims.zero? }),
      Step.new(stage: "scoring", job: "ScoreFindingsJob",
               complete: ->(facts) { facts.unscored_findings.zero? }),
      Step.new(stage: "auditing_coverage", job: "AuditCoverageJob",
               complete: ->(facts) { facts.coverage_audited }),
      Step.new(stage: "creating_chatbot", job: "CreateChatbotJob",
               complete: ->(facts) { facts.chatbot.present? })
    ].freeze

    LABELS = {
      "mapping" => "Mapping website",
      "classifying" => "Recognising page types",
      "planning" => "Building crawl plan",
      "crawling" => "Reading content",
      "processing" => "Preparing passages",
      "embedding" => "Building search index",
      "analyzing" => "Understanding the company",
      "extracting_claims" => "Reading what they published",
      "checking_visibility" => "Checking what a buyer can find",
      "scoring" => "Ranking opportunities",
      "auditing_coverage" => "Checking what they never answer",
      "creating_chatbot" => "Creating demo"
    }.freeze

    def initialize(scan)
      @scan = scan
    end

    # Enqueues the work for whichever stage is next, or finalizes the scan when
    # every stage is behind us. Safe to call from anywhere, any number of times.
    def advance!
      scan.with_lock do
        return if scan.finished?

        # Re-read facts under the lock: a job finishing late must not move the
        # pipeline backwards using a snapshot from before another job finished.
        @facts = nil
        step = next_step
        return FinalizeScanJob.perform_later(scan) if step.nil?

        step.job_class.perform_later(scan) if scan.claim_stage(step.stage)
      end
    end

    def next_step = STEPS.reject { |step| step.complete?(facts) }.first

    # Gathered once per instance. Callers that need fresh numbers build a new
    # pipeline, which is what every request already does.
    def facts
      @facts ||= begin
        # The page types are a frozen constant, but they are still quoted by
        # Active Record rather than pasted in: a type containing an apostrophe
        # would otherwise produce invalid SQL and a confusing failure.
        indexable = ApplicationRecord.sanitize_sql_array([ "array[?]::varchar[]", PageTypes.indexable ])
        pages = scan.pages.pick(Arel.sql(<<~SQL)) || [ 0, 0, 0 ]
          count(*),
          count(*) filter (where indexed),
          count(*) filter (where not indexed and page_type = any (#{indexable}))
        SQL
        chunks = scan.chunks.pick(Arel.sql("count(*), count(*) filter (where embedded_at is null)")) || [ 0, 0 ]
        urls = scan.discovered_urls.pick(Arel.sql(<<~SQL)) || [ 0, 0, 0, 0 ]
          count(*),
          count(*) filter (where selected_for_crawl),
          count(*) filter (where selected_for_crawl and crawled_at is null),
          count(*) filter (where metadata ->> 'reason' like 'classified by%')
        SQL
        claims = scan.claims.pick(Arel.sql(<<~SQL)) || [ 0, 0 ]
          count(*), count(*) filter (where status in ('pending', 'checking'))
        SQL
        findings = scan.findings.pick(Arel.sql("count(*) filter (where status = 'viable'), count(*) filter (where status = 'pending')")) || [ 0, 0 ]
        profile = scan.company_profile

        Facts.new(
          discovered: urls[0].positive?, urls_discovered: urls[0],
          planned: scan.plan_summary.present?, pages_selected: urls[1], uncrawled: urls[2],
          classified: scan.urls_classified_at.present?, refined: urls[3],
          pages_crawled: pages[0], pages_indexed: pages[1],
          unchunked: pages[2], chunks: chunks[0], unembedded: chunks[1],
          profiled: profile.present?, category: profile&.product_category,
          claims_extracted: scan.claims_extracted_at.present?,
          claims_total: claims[0], unresolved_claims: claims[1], claims_checked: claims[0] - claims[1],
          findings: findings[0], unscored_findings: findings[1],
          coverage_audited: scan.coverage_audited_at.present?,
          chatbot: scan.chatbot
        )
      end
    end

    def complete? = next_step.nil?

    # What the progress UI walks: every stage, with what it produced.
    #
    # A stage's own predicate is vacuously true before the pipeline reaches it
    # -- there are no unembedded chunks before there are any chunks -- so
    # everything past the current stage is reported as pending regardless of
    # what its predicate says. Orderings, not predicates, decide what is done.
    def progress
      upcoming = next_step
      reached_upcoming = false

      STEPS.map do |step|
        current = upcoming && step.stage == upcoming.stage
        reached_upcoming ||= current

        state =
          if scan.failed? && scan.failed_stage == step.stage then "failed"
          elsif current && !scan.failed? then "active"
          elsif reached_upcoming && !current then "pending"
          elsif step.complete?(facts) then "complete"
          else "pending"
          end

        { stage: step.stage, label: label_for(step.stage), state: state, detail: detail_for(step.stage) }
      end
    end

    private
      attr_reader :scan

      def label_for(stage)
        return "Understanding #{scan.lead.name}" if stage == "analyzing"

        LABELS.fetch(stage, stage.humanize)
      end

      def detail_for(stage)
        case stage
        when "mapping" then counted(facts.urls_discovered, "URL", "discovered")
        when "classifying" then classified_detail
        when "planning" then planned_detail
        when "crawling" then facts.pages_selected.positive? ? "#{delimited(facts.pages_crawled)} / #{delimited(facts.pages_selected)} pages" : nil
        when "processing" then counted(facts.pages_indexed, "page", "prepared")
        when "embedding" then counted(facts.chunks, "passage", "indexed")
        when "analyzing" then facts.category
        when "extracting_claims" then counted(facts.claims_total, "claim", "found")
        when "checking_visibility" then checked_detail
        when "scoring" then counted(facts.findings, "gap", "found")
        when "auditing_coverage" then counted(scan.findings.where(kind: "missing").count, "unanswered question", "found")
        when "creating_chatbot" then facts.chatbot&.name
        end
      end

      # The mapped count is every public URL the site admits to, which on a big
      # site is thousands and reliably reads as "it is about to crawl all of
      # that". Naming the budget next to it is the difference between alarm and
      # information.
      def planned_detail
        selected = counted(facts.pages_selected, "relevant page", "selected")
        return selected if selected.nil?

        "#{selected} of #{delimited(WebsiteIntelligence.config.max_pages_per_scan)} allowed"
      end

      def classified_detail
        return nil unless facts.classified

        facts.refined.zero? ? "all recognised by rules" : counted(facts.refined, "URL", "recognised by model")
      end

      def checked_detail
        return nil if facts.claims_total.zero?

        "#{facts.claims_checked} / #{facts.claims_total}"
      end

      # Only the noun is pluralized. "23 URL discovereds" is the kind of detail
      # that makes a product feel unfinished.
      def counted(count, noun, verb)
        return nil if count.to_i.zero?

        "#{delimited(count)} #{noun.pluralize(count)} #{verb}"
      end

      def delimited(number) = ActiveSupport::NumberHelper.number_to_delimited(number.to_i)
  end
end
