# frozen_string_literal: true

# The enterprise questions a buyer will ask of anyone, checked against
# everything a company published.
#
#   CoverageAudit.new(scan).gaps
#
# Claim extraction finds what a company buried. It finds nothing at all for the
# many companies whose public content is a marketing site and little else -- and
# for those, silence is the finding. A buyer evaluating them will ask about SSO,
# data residency and recovery objectives regardless, and "answered nowhere on
# the site" is exactly what a salesperson wants to open with.
class CoverageAudit
  # The fallback, used in fake mode and whenever a company's own category is
  # unknown. It is deliberately SaaS-shaped, which is exactly why it cannot be
  # the only list: asking a 3D-printing manufacturer whether it supports SCIM
  # produces a finding that is true, unanswerable and completely useless.
  DEFAULT_CHECKLIST = {
    "SSO" => { question: "Does %{company} support SAML single sign-on?", category: "security_compliance", importance: 0.9 },
    "SCIM" => { question: "Does %{company} support SCIM user provisioning?", category: "security_compliance", importance: 0.82 },
    "RBAC" => { question: "Can administrators control who sees what in %{company}?", category: "enterprise_controls", importance: 0.88 },
    "SOC 2" => { question: "Has %{company} completed a SOC 2 audit?", category: "security_compliance", importance: 0.85 },
    "data residency" => { question: "Where does %{company} store customer data?", category: "data_governance", importance: 0.84 },
    "audit logs" => { question: "Does %{company} provide an audit log?", category: "data_governance", importance: 0.78 },
    "encryption" => { question: "How does %{company} encrypt customer data?", category: "security_compliance", importance: 0.72 },
    "SLA" => { question: "What uptime does %{company} commit to?", category: "reliability", importance: 0.8 },
    "RPO/RTO" => { question: "What are %{company}'s recovery objectives after an outage?", category: "reliability", importance: 0.76 },
    "backups" => { question: "How does %{company} back up and restore customer data?", category: "reliability", importance: 0.7 },
    "rate limits" => { question: "Does %{company} publish API rate limits?", category: "api", importance: 0.68 },
    "retention" => { question: "How long does %{company} retain customer data?", category: "data_governance", importance: 0.7 },
    "GDPR" => { question: "How does %{company} handle GDPR obligations?", category: "data_governance", importance: 0.72 },
    "migration" => { question: "What does onboarding or migration to %{company} involve?", category: "migration", importance: 0.74 }
  }.freeze

  # Above this the topic is covered somewhere, however briefly, so its absence
  # is not the story.
  COVERED_CONFIDENCE = 0.35

  # "They publish nothing about SSO" is a claim about the site, and it needs the
  # site to have been read. Below this we know too little to assert an absence,
  # and saying nothing is better than saying something unfounded.
  MINIMUM_PASSAGES = 20

  Gap = Data.define(:topic, :question, :category, :importance, :confidence)

  QUESTIONS_SCHEMA = {
    type: "object",
    additionalProperties: false,
    required: %w[questions],
    properties: {
      questions: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: %w[topic question category importance],
          properties: {
            topic: { type: "string" },
            question: { type: "string" },
            category: { type: "string", enum: Claim::CATEGORIES },
            importance: { type: "number", minimum: 0, maximum: 1 }
          }
        }
      }
    }
  }.freeze

  def initialize(scan, answerer: nil)
    @scan = scan
    @answerer = answerer || AI::Answerer.build(scan)
  end

  # Topics the company answers nowhere in anything we indexed.
  def gaps
    return [] unless corpus_sufficient?

    # One provider call per question, each around twelve seconds, and no
    # question depends on the answer to another -- so they overlap rather than
    # queue. The topics already covered are dropped first, because the cheapest
    # call is the one that is never made.
    outstanding = checklist.reject { |topic, _| extracted_topics.include?(topic) }

    @gaps ||= BoundedParallel.map(outstanding, limit: concurrency) do |topic, spec|
      # Generated questions already name the company; the fallback templates do not.
      raw = spec.fetch(:question)
      question = raw.include?("%{company}") ? format(raw, company: company) : raw
      result = answerer.answer(question, scope: :all)
      next if result.answerable? || result.coverage >= COVERED_CONFIDENCE

      Gap.new(topic: topic, question: question, category: spec.fetch(:category),
              importance: spec.fetch(:importance), confidence: result.coverage)
    end.compact
  end

  def concurrency = WebsiteIntelligence.config.provider_call_concurrency

  def corpus_sufficient? = scan.chunks.embedded.count >= MINIMUM_PASSAGES

  # What a buyer of *this* would ask any vendor in this category.
  #
  # Derived from the company's own profile rather than from a fixed list,
  # because "what every enterprise buyer asks" is not a universal set: it is
  # SSO and data residency for a software vendor, and tolerances, lead times
  # and certifications for a manufacturer.
  def checklist
    @checklist ||= (WebsiteIntelligence.live_ai_enabled? && generated_checklist.presence) || DEFAULT_CHECKLIST
  end

  private
    attr_reader :scan, :answerer

    def generated_checklist
      category = scan.company_profile&.product_category
      return nil if category.blank?

      response = AI::Client.new(model: AI::Models.fast, operation: "coverage_checklist", scan: scan).structured(
        schema: QUESTIONS_SCHEMA,
        instructions: <<~TEXT,
          You list the questions a serious buyer asks any vendor in a given category before
          committing -- the ones that stall a deal when a website does not answer them.

          Judge from the category itself. A software vendor is asked about single sign-on,
          data residency and uptime commitments. A manufacturer is asked about tolerances,
          materials, lead times, capacity, certifications and minimum orders. A services
          firm is asked about scope, timelines and team composition. Ask what fits this
          category, not what fits software.

          Give 10 to 14 questions, each about a distinct topic, each answerable by a vendor
          that publishes thoroughly. Do not mention the company by name in the topic.
        TEXT
        prompt: <<~TEXT
          Category: #{category}
          Company sells: #{Array(scan.company_profile&.products).first(6).join(', ').presence || 'not stated'}
          Their own content raises: #{Array(scan.company_profile&.enterprise_concerns).first(8).join(', ').presence || 'nothing specific'}

          List what a buyer would ask any vendor in this category. Write each question about
          "#{company}" by name.
        TEXT
      )

      Array(response["questions"]).to_h do |row|
        [ row["topic"].to_s,
          { question: row["question"].to_s, category: row["category"], importance: row["importance"].to_f } ]
      end.reject { |topic, spec| topic.blank? || spec[:question].blank? }
    rescue AI::Client::ResponseError, SpendingLimit::Exceeded => error
      Rails.logger.warn("CoverageAudit checklist generation failed for scan #{scan.id}: #{error.message}")
      nil
    end

    def company = scan.lead.name

    def extracted_topics = @extracted_topics ||= scan.claims.where.not(topic: nil).distinct.pluck(:topic).to_set
end
