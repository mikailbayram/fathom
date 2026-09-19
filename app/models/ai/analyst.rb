# frozen_string_literal: true

module AI
  # Builds the structured understanding of a company that question generation
  # depends on: what it sells, who buys it, what it integrates with, and which
  # enterprise concerns its own content raises.
  #
  #   AI::Analyst.build(scan).profile
  #
  class Analyst
    Profile = Data.define(
      :company_name, :description, :product_category, :buyer_personas, :products,
      :integrations, :enterprise_features, :enterprise_concerns, :raw
    ) do
      def to_attributes
        {
          company_name: company_name, description: description, product_category: product_category,
          buyer_personas: buyer_personas, products: products, integrations: integrations,
          enterprise_features: enterprise_features, enterprise_concerns: enterprise_concerns,
          raw_analysis: raw
        }
      end
    end

    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[company_name description product_category buyer_personas products integrations enterprise_features enterprise_concerns],
      properties: {
        company_name: { type: "string" },
        description: { type: "string" },
        product_category: { type: "string" },
        buyer_personas: { type: "array", items: { type: "string" } },
        products: { type: "array", items: { type: "string" } },
        integrations: { type: "array", items: { type: "string" } },
        enterprise_features: { type: "array", items: { type: "string" } },
        enterprise_concerns: { type: "array", items: { type: "string" } }
      }
    }.freeze

    def self.build(scan) = WebsiteIntelligence.live_ai_enabled? ? Live.new(scan) : Fake.new(scan)

    def initialize(scan, model: Models.analysis)
      @scan = scan
      @model = model
    end

    def profile = raise NotImplementedError

    private
      attr_reader :scan, :model

      # The pages worth reading to understand a company: buyer-facing first,
      # then the substantial technical ones.
      def representative_pages(limit: 40)
        @representative_pages ||= scan.pages
          .where(page_type: PageTypes.indexable)
          .order(Arel.sql("CASE corpus_type WHEN 'buyer_visible' THEN 0 ELSE 1 END, word_count DESC"))
          .limit(limit)
          .to_a
      end
  end
end
