# frozen_string_literal: true

module AI
  # Reads the deep public corpus and pulls out the specific, checkable claims a
  # company has actually published.
  #
  #   AI::Extractor.build(scan).claims
  #
  # This is where gaps come from. Nothing here guesses what an enterprise buyer
  # might ask: it reads what the company wrote and surfaces the statements that
  # would matter during an evaluation, each still attached to the passage it
  # came from. A site whose documentation says something unusual produces an
  # unusual claim, which a fixed question list could never have found.
  class Extractor
    Claim = Data.define(:chunk_id, :statement, :question, :category, :importance, :topic, :support) do
      def to_attributes(scan)
        {
          scan_id: scan.id,
          chunk_id: chunk_id,
          statement: statement,
          question_text: question,
          category: category,
          buyer_importance: importance,
          topic: topic,
          support: support,
          status: "pending"
        }
      end
    end

    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[claims],
      properties: {
        claims: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[chunk_id statement question category importance],
            properties: {
              chunk_id: { type: "integer" },
              statement: { type: "string" },
              question: { type: "string" },
              category: { type: "string", enum: ::Claim::CATEGORIES },
              importance: { type: "number", minimum: 0, maximum: 1 }
            }
          }
        }
      }
    }.freeze

    def self.build(scan)
      klass = WebsiteIntelligence.live_ai_enabled? ? Live : Fake
      klass.new(scan)
    end

    def initialize(scan, model: Models.analysis)
      @scan = scan
      @model = model
    end

    def claims
      @claims ||= begin
        extracted = BoundedParallel.map(passages.each_slice(batch_size), limit: concurrency) do |batch|
          extract(batch)
        end.flatten(1)
        verified = extracted.select { |claim| claim.support >= ::Claim::MINIMUM_SUPPORT && checkable?(claim.statement) }

        verified
          # Two concerns can lift overlapping sentences from one passage. The
          # opening of a statement is enough to recognise that as one claim.
          .uniq { |claim| [ claim.chunk_id, claim.statement.to_s.downcase.squish.first(90) ] }
          .uniq { |claim| claim.statement.to_s.downcase.squish }
          # A salesperson does not want the same question three times because
          # three passages happened to touch the same concern. Best-supported
          # statement wins, and the rest of that concern's evidence is still in
          # the corpus for the chatbot to use.
          .uniq { |claim| claim.question.to_s.downcase.squish }
          .sort_by { |claim| [ -claim.importance, -claim.support ] }
          .first(WebsiteIntelligence.config.max_claims_per_scan)
      end
    end

    # The passages worth reading, ranked by how much concrete information they
    # carry and how buried they are, then capped so a large site costs a bounded
    # amount.
    #
    # This used to require a passage to mention SSO, SCIM, RBAC or a named SaaS
    # integration. That silently excluded every company that is not a SaaS
    # vendor: a 3D-printing manufacturer whose data sheets quote build volumes
    # and tolerances scored zero and was never read at all. What a buyer
    # evaluates on differs by industry, and deciding it from a fixed vocabulary
    # was the wrong shape -- the model reading the passage can tell.
    def passages
      @passages ||= scan.chunks
        .embedded
        .where(corpus_type: CorpusTypes::RETRIEVABLE)
        .to_a
        .map { |chunk| [ chunk, information_density(chunk) ] }
        .select { |_, weight| weight.positive? }
        .sort_by { |chunk, weight| [ -weight, chunk.id ] }
        .first(WebsiteIntelligence.config.max_claim_passages)
        .map(&:first)
    end

    private
      attr_reader :scan, :model

      def batch_size = WebsiteIntelligence.config.claim_extraction_batch

      def concurrency = WebsiteIntelligence.config.provider_call_concurrency

      def extract(_batch) = raise NotImplementedError

      def company = scan.lead.name

      # Numbers, units, standards and named systems are what a checkable claim is
      # made of, in any industry: "up to 50 custom roles", "400 x 400 x 400 mm",
      # "ISO 9001", "6-8 weeks", "99.9%". Prose with none of them is positioning,
      # not a fact a buyer can hold anyone to.
      MEASUREMENT = /\d/
      UNIT = /\b(?:mm|cm|kg|lbs?|hours?|days?|weeks?|months?|years?|%|µm|um|mpa|psi|rpm|watts?|kw|
                  gb|tb|rps|qps|requests?|users?|seats?)\b/xi
      STANDARD = /\b(?:ISO|ASTM|ANSI|DIN|IEC|SOC|NIST|CMMC|FDA|CE|UL|RoHS|REACH|IATF|AS\d|ITAR)\b/
      HEDGE = /\b(?:only|not|cannot|excluded|unsupported|requires?|minimum|maximum|up to|at least)\b/i

      def information_density(chunk)
        body = chunk.body
        return 0 if body.length < 80

        score = 0
        score += 3 if body.match?(MEASUREMENT)
        score += 2 if body.match?(UNIT)
        score += 3 if body.match?(STANDARD)
        score += 2 if body.match?(HEDGE)
        # Anything the company's own analysis flagged as a concern still counts,
        # it is simply no longer the only way in.
        score += 2 if profile_terms.any? { |term| body.downcase.include?(term) }
        return 0 if score.zero?

        score + FrictionScore::OBSCURITY.fetch(chunk.page_type.to_s, 3)
      end

      # The vocabulary this company actually uses, taken from the profile the
      # analyst built out of their own pages rather than from a list we wrote.
      def profile_terms
        @profile_terms ||= begin
          profile = scan.company_profile
          terms = Array(profile&.enterprise_concerns) + Array(profile&.named_integrations) +
                  Array(profile&.products)
          terms.map { |term| term.to_s.downcase }.select { |term| term.length > 3 }
        end
      end

      # A heading, a nav list or a sentence of throat-clearing is not a claim.
      # A claim asserts something a buyer could hold the company to: a
      # capability, a limit, a period, a plan restriction.
      ASSERTIVE = /\b(?:can|cannot|must|may|supports?|does not|is|are|has|have|includes?|enforces?|
                       retains?|requires?|provides?|offers?|commits?|allows?|limits?|available|
                       up to|takes?|stores?|encrypts?|retries|uses?|maintains?|holds?|
                       certified|complies|complete[ds]?)\b/xi
      # A claim is specific if it quantifies, names a standard, or names a tier --
      # not only if it mentions a SaaS plan.
      SPECIFIC = /\d|\b(?:Enterprise|Business|Starter|Growth|Pro|Premium|Team)\b|#{STANDARD.source}/
      NEGATIVE = /\b(?:cannot|does not|not supported|only|never)\b/i
      LIST_SHAPED = /\A\s*[-*•]|\s[-*•]\s.*\s[-*•]\s/

      def checkable?(statement)
        text = statement.to_s.squish
        return false if text.length < 30
        return false if text.match?(LIST_SHAPED)

        text.match?(ASSERTIVE) && (text.match?(SPECIFIC) || text.match?(NEGATIVE))
      end

      # A claim is only kept if the passage it cites actually says it. This is
      # the guard against an extractor writing a plausible sentence the company
      # never published.
      def support_for(statement, chunk)
        return 0.0 if chunk.nil?

        Answerer::Terms.new(statement).coverage(chunk.body)
      end
  end
end
