# frozen_string_literal: true

# Shapes one lead -- the company, its latest scan, its gaps and its demo -- for
# the single page that represents it.
class LeadPresenter
  def initialize(lead, origin: nil)
    @lead = lead
    @origin = origin
  end

  def row
    {
      id: lead.id,
      name: lead.name,
      domain: lead.domain,
      website_url: lead.website_url,
      scans_count: lead.scans.size,
      status: scan&.status,
      running: scan&.running? || false,
      failed: scan&.failed? || false,
      stalled: scan&.stalled? || false,
      waiting_for_slot: waiting_for_slot?,
      # The stage, in the words the progress list uses. A row that says
      # "Scanning" for eleven minutes is indistinguishable from a stuck one.
      stage_label: stage_label,
      findings_count: scan&.findings_count.to_i,
      claims_count: scan&.claims_count.to_i,
      pages_crawled: scan&.pages_crawled.to_i,
      scanned_at: scan&.completed_at,
      demo_path: demo&.fetch(:path)
    }
  end

  def detail
    row.merge(
      metrics: metrics,
      profile: profile,
      plan: scan&.plan_summary || {},
      findings: findings.map { |finding| FindingPresenter.new(finding).row },
      categories: findings.map(&:category).uniq.sort,
      claims_found: scan&.claims&.count.to_i,
      demo: demo,
      handoffs: handoffs,
      waiting_handoffs: handoffs.count { |handoff| handoff[:status] == "waiting" },
      mode: scan&.mode
    )
  end

  def status
    return { present: false, steps: [], running: false, failed: false } if scan.nil?

    {
      present: true,
      scan_id: scan.id,
      status: scan.status,
      running: scan.running?,
      failed: scan.failed?,
      stalled: scan.stalled?,
      # Carried on the live payload as well as the row: the page renders its
      # header from whichever arrived most recently, and a field missing from
      # one of them reads as a state that changed.
      waiting_for_slot: waiting_for_slot?,
      stage_label: stage_label,
      failed_stage: scan.failed_stage,
      failed_stage_label: failed_stage_label,
      error_message: scan.error_message,
      metrics: metrics,
      steps: scan.pipeline.progress
    }
  end

  private
    attr_reader :lead

    def scan = @scan ||= lead.latest_scan

    def findings
      return [] if scan.nil?

      @findings ||= scan.findings.viable.ranked.includes(:claim, :scan, finding_sources: { chunk: :page }).to_a
    end

    def metrics
      return {} if scan.nil?

      {
        urls_discovered: scan.urls_discovered,
        pages_crawled: scan.pages_crawled,
        chunks: scan.chunks_count,
        claims: scan.claims_count,
        findings: scan.findings_count,
        # What it cost to produce all of the above. One number: the breakdown
        # between the models and the crawler is an operator's question, and the
        # console answers it.
        cost: ScanCost.new(scan).to_payload
      }
    end

    # Looked up in the labels the pipeline already publishes rather than built
    # from a second copy of them.
    def stage_label
      return nil if scan.nil? || !scan.running?
      return "Queued" if scan.pending?

      Scan::Pipeline::LABELS.fetch(scan.status, scan.status.humanize)
    end

    def waiting_for_slot?
      scan.present? && scan.running? && (scan.pending? || scan.work.blocked?)
    end

    def profile
      record = scan&.company_profile
      return nil if record.nil?

      {
        description: record.description,
        product_category: record.product_category,
        integrations: record.named_integrations,
        enterprise_concerns: record.concerns
      }
    end

    def demo
      chatbot = scan&.chatbot
      return nil if chatbot.nil?

      {
        name: chatbot.name,
        slug: chatbot.slug,
        path: Rails.application.routes.url_helpers.public_demo_path(chatbot.slug),
        public: chatbot.publicly_shared?,
        suggested_questions: chatbot.suggested_questions(limit: 4),
        # A console one-liner, not a script tag: this is pasted into the
        # prospect's own devtools, which cannot execute HTML.
        widget_snippet: widget_snippet(chatbot)
      }
    end

    # Questions the agent could not answer, newest first, so a salesperson sees
    # what their own website is failing to say.
    def handoffs
      chatbot = scan&.chatbot
      return [] if chatbot.nil?

      @handoffs ||= chatbot.handoffs.order(status: :asc, created_at: :desc).limit(50).map(&:to_payload)
    end

    # Appends the loader to whatever page it is run on.
    def widget_snippet(chatbot)
      src = "#{@origin}/d/#{chatbot.slug}/widget.js"
      "var s=document.createElement('script');s.src='#{src}';s.async=true;document.body.appendChild(s);"
    end

    def failed_stage_label
      return nil if scan.failed_stage.blank?

      Scan::Pipeline::LABELS.fetch(scan.failed_stage, scan.failed_stage.humanize)
    end
end
