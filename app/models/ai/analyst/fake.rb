# frozen_string_literal: true

module AI
  class Analyst
    # Derives the company profile from the indexed corpus with deterministic
    # rules instead of a model.
    #
    # It reads the same pages the live analyst reads and returns the same
    # structure, so question generation, the UI and the chatbot's system prompt
    # are all exercised for real.
    class Fake < Analyst
      def profile
        pages = representative_pages
        corpus = pages.map { |page| "#{page.title} #{page.content}" }.join("\n")
        homepage = pages.detect(&:page_type_homepage?) || pages.first
        concerns = Lexicon.concerns_in(corpus)

        Profile.new(
          company_name: scan.lead.name,
          description: description_from(homepage),
          product_category: category_from(corpus, homepage),
          buyer_personas: Lexicon.personas_for(concerns),
          products: products_from(pages),
          integrations: Lexicon.integrations_in(corpus),
          enterprise_features: features_in(corpus),
          enterprise_concerns: concerns,
          raw: { "adapter" => "fake", "pages_read" => pages.size, "model" => "deterministic" }
        )
      end

      private
        def description_from(page)
          return "No public description was found." if page.nil?

          page.content.to_s.split(/(?<=[.!?])\s+/).first(2).join(" ").squish.presence ||
            page.title.presence || "No public description was found."
        end

        # The category comes from the company's own words where it states them,
        # and from its vocabulary where it does not. Never invented.
        def category_from(corpus, homepage)
          stated = homepage&.content.to_s[/\b(?:is|provides|builds|offers)\s+(?:a|an|the)\s+([a-z0-9][^.,;]{8,80})/i, 1]
          # Kept to whole words: a category clipped mid-word is worse than a
          # shorter one.
          return stated.squish.split.first(5).join(" ").upcase_first if stated.present?

          haystack = corpus.downcase
          {
            "Enterprise data integration" => %w[warehouse pipeline sync ingestion],
            "Developer platform" => %w[api sdk webhook endpoint],
            "Security and compliance platform" => %w[soc compliance audit policy],
            "Business software" => []
          }.max_by { |_, markers| markers.count { |marker| haystack.include?(marker) } }.first
        end

        def products_from(pages)
          pages.select { |page| page.page_type_product? || page.page_type_solution? }
               .filter_map { |page| page.title.presence }.uniq.first(8)
        end

        def features_in(corpus)
          haystack = corpus.downcase
          {
            "Custom roles" => "custom role",
            "Audit logging" => "audit log",
            "SAML SSO" => "saml",
            "SCIM provisioning" => "scim",
            "Data residency controls" => "data residency",
            "Webhook delivery guarantees" => "webhook",
            "Enterprise SLA" => "sla"
          }.filter_map { |feature, marker| feature if haystack.include?(marker) }
        end
    end
  end
end
