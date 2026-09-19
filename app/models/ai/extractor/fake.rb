# frozen_string_literal: true

module AI
  class Extractor
    # Deterministic extraction, driven by the passage rather than by a template.
    #
    # For each enterprise concern a passage genuinely raises, it lifts the
    # sentences that carry it and phrases the question those sentences answer.
    # The claims differ from site to site because the passages do.
    class Fake < Extractor
      # concern -> how to phrase the buyer question it answers.
      QUESTIONS = {
        "RBAC" => "Can administrators define custom roles in %{company}?",
        "SSO" => "How does single sign-on work with %{company}, and which plan includes it?",
        "SCIM" => "Does %{company} support SCIM provisioning and deprovisioning?",
        "audit logs" => "What does %{company} record in its audit log, and for how long?",
        "data residency" => "Where does %{company} store customer data, and can the region be chosen?",
        "encryption" => "How does %{company} encrypt customer data?",
        "retention" => "How long does %{company} retain customer data?",
        "SOC 2" => "Which compliance certifications has %{company} completed?",
        "HIPAA" => "Is %{company} able to support HIPAA workloads?",
        "GDPR" => "How does %{company} handle GDPR obligations such as erasure?",
        "ISO 27001" => "Which security certifications does %{company} hold?",
        "rate limits" => "What API rate limits does %{company} enforce?",
        "webhooks" => "How does %{company} handle webhook delivery and failure?",
        "SLA" => "What uptime does %{company} commit to?",
        "RPO/RTO" => "What are %{company}'s documented recovery objectives?",
        "backups" => "How does %{company} back up and restore customer data?",
        "migration" => "What does a migration to %{company} involve?",
        "API reliability" => "How does %{company} behave when a request or sync fails?",
        "permissions" => "How granular are %{company}'s permissions?",
        "integration limits" => "What are the limits of %{company}'s integrations?"
      }.freeze

      CATEGORIES = {
        "RBAC" => "enterprise_controls", "SSO" => "security_compliance", "SCIM" => "security_compliance",
        "audit logs" => "data_governance", "data residency" => "data_governance", "encryption" => "security_compliance",
        "retention" => "data_governance", "SOC 2" => "security_compliance", "HIPAA" => "security_compliance",
        "GDPR" => "data_governance", "ISO 27001" => "security_compliance", "rate limits" => "api",
        "webhooks" => "api", "SLA" => "reliability", "RPO/RTO" => "reliability", "backups" => "reliability",
        "migration" => "migration", "API reliability" => "api", "permissions" => "enterprise_controls",
        "integration limits" => "integrations"
      }.freeze

      # Concerns a buyer's security review or procurement actually blocks on.
      IMPORTANCE = {
        "RBAC" => 0.95, "SSO" => 0.9, "SCIM" => 0.88, "data residency" => 0.87, "RPO/RTO" => 0.85,
        "rate limits" => 0.84, "webhooks" => 0.84, "audit logs" => 0.82, "SLA" => 0.81, "migration" => 0.8,
        "permissions" => 0.78, "retention" => 0.75, "SOC 2" => 0.74, "encryption" => 0.7, "backups" => 0.7,
        "API reliability" => 0.7, "GDPR" => 0.68, "ISO 27001" => 0.66, "HIPAA" => 0.62,
        "integration limits" => 0.9
      }.freeze

      def extract(batch)
        batch.flat_map { |chunk| claims_in(chunk) }
      end

      private
        def claims_in(chunk)
          Lexicon.concerns_in(chunk.content).filter_map do |concern|
            statement = statement_for(chunk, concern)
            next if statement.blank?

            Claim.new(
              chunk_id: chunk.id,
              statement: statement,
              question: question_for(chunk, concern),
              category: CATEGORIES.fetch(concern, "security_compliance"),
              importance: IMPORTANCE.fetch(concern, 0.6),
              topic: concern,
              support: support_for(statement, chunk)
            )
          end
        end

        # An integration limit is only meaningful with the system it applies to,
        # which the passage names.
        def question_for(chunk, concern)
          if concern == "integration limits" && (system = Lexicon.integrations_in(chunk.content).first)
            return "Does #{company}'s #{system} integration have limits a buyer should know about?"
          end

          format(QUESTIONS.fetch(concern, "What does %{company} document about #{concern}?"), company: company)
        end

        # Qualifies a capability: which plan it needs, or what limit applies.
        QUALIFIER = /\b(?:Enterprise|Business|Starter|Growth|Pro|Premium|Team)\s+plan\b|\b\d/

        # The sentences in this passage that actually carry the concern, which is
        # what makes the claim checkable rather than a paraphrase.
        #
        # The sentence that follows is pulled in when it qualifies the one that
        # matched: "custom roles can be defined" without "on the Enterprise plan"
        # is half a claim, and the half that is missing is the half a buyer cares
        # about.
        def statement_for(chunk, concern)
          markers = Lexicon::ENTERPRISE_CONCERNS.fetch(concern, [])
          sentences = chunk.body.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:blank?)

          selected = sentences.each_with_index.select do |sentence, _|
            markers.any? { |marker| Lexicon.mentions?(sentence.downcase, marker) }
          end.first(2)
          return nil if selected.empty?

          indexes = selected.map(&:last)
          following = indexes.last + 1
          indexes << following if sentences[following]&.match?(QUALIFIER) && !indexes.include?(following)

          indexes.sort.map { |index| sentences[index] }.join(" ").squish.presence
        end
    end
  end
end
