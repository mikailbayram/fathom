# frozen_string_literal: true

module AI
  # The enterprise vocabulary the deterministic objects recognise, and the terms
  # scoring treats as technically specific.
  #
  # Keeping it in one place means the fake analyst, the fake interviewer and the
  # friction score all agree on what "technical" means.
  module Lexicon
    INTEGRATIONS = %w[
      Snowflake Databricks Salesforce NetSuite Workday HubSpot Segment BigQuery
      Redshift Okta OneLogin Azure AWS Slack Jira ServiceNow Zendesk SAP Oracle
      Stripe Shopify Marketo Tableau Looker Kafka Postgres MongoDB Terraform
      Datadog Splunk Kubernetes GitHub GitLab
    ].freeze

    # Term -> the buyer concern it signals.
    ENTERPRISE_CONCERNS = {
      "RBAC" => %w[rbac role-based],
      "SSO" => %w[sso saml single sign-on],
      "SCIM" => %w[scim provisioning deprovisioning],
      "audit logs" => [ "audit log", "audit trail" ],
      "data residency" => [ "data residency", "data region", "residency" ],
      "encryption" => %w[encryption encrypted aes tls],
      "retention" => %w[retention retained],
      "SOC 2" => [ "soc 2", "soc2" ],
      "HIPAA" => %w[hipaa],
      "GDPR" => %w[gdpr],
      "ISO 27001" => [ "iso 27001", "iso27001" ],
      "rate limits" => [ "rate limit", "throttl" ],
      "webhooks" => %w[webhook],
      "SLA" => [ "sla", "uptime", "service level" ],
      "RPO/RTO" => %w[rpo rto],
      "backups" => %w[backup],
      "migration" => %w[migration migrate],
      "API reliability" => [ "retry", "retries", "idempoten", "failover" ],
      "permissions" => %w[permission granular],
      # What a connector will and will not do is among the most valuable things
      # a vendor buries, and it is never phrased in security vocabulary.
      "integration limits" => [ "one-way", "two-way", "bidirectional", "read-only", "not supported",
                                "sync direction", "synchronization direction", "writing changes back" ]
    }.freeze

    # Acronyms and identifiers whose exact form matters to a buyer, which is why
    # lexical retrieval exists alongside vectors.
    TECHNICAL_TERMS = %w[
      rbac sso saml scim soc hipaa gdpr iso fedramp pci rpo rto sla api oauth
      webhook webhooks jwt mfa vpc cidr tls aes sdk graphql rest sftp idp dpa
      ccpa hsm kms 429 503
    ].to_set.freeze

    # Deliberate prefixes: these match inflected forms rather than whole words.
    STEM_MARKERS = %w[throttl idempoten].to_set.freeze

    PERSONA_RULES = {
      "Security & Compliance" => [ "RBAC", "SSO", "SCIM", "encryption", "SOC 2", "HIPAA", "ISO 27001", "audit logs" ],
      "Enterprise IT" => [ "SSO", "SCIM", "data residency", "permissions" ],
      "Engineering" => [ "webhooks", "rate limits", "API reliability" ],
      "Platform / Data Engineering" => [ "migration", "backups" ],
      "Procurement" => [ "SLA", "retention" ]
    }.freeze

    module_function

    def integrations_in(text)
      haystack = text.to_s.downcase
      INTEGRATIONS.select { |name| mentions?(haystack, name.downcase) }
    end

    def concerns_in(text)
      haystack = text.to_s.downcase
      ENTERPRISE_CONCERNS.filter_map do |concern, markers|
        concern if markers.any? { |marker| mentions?(haystack, marker) }
      end
    end

    # Whole words only. Substring matching reads "subprocessors" as SSO and
    # "migration" inside "immigration", which quietly mislabels evidence and
    # then mislabels every finding built on it.
    def mentions?(haystack, marker)
      # A few markers are deliberate stems, matching inflected forms.
      pattern = STEM_MARKERS.include?(marker) ? /\b#{Regexp.escape(marker)}/ : /\b#{Regexp.escape(marker)}\b/
      haystack.match?(pattern)
    end

    def personas_for(concerns)
      PERSONA_RULES.filter_map { |persona, triggers| persona if (triggers & concerns).any? }.presence || [ "Enterprise IT" ]
    end

    def technical?(term) = TECHNICAL_TERMS.include?(term.to_s.downcase)
  end
end
