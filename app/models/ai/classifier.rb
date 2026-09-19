# frozen_string_literal: true

module AI
  # Classifies the URLs the deterministic rules could not recognise.
  #
  #   AI::Classifier.build(scan).refine!
  #
  # This is the one place the cheap model earns its keep. The rules in
  # Url::Classification are written in English and cover the shapes most SaaS
  # sites use; a site that names its pages in Norwegian, or puts its docs
  # somewhere unusual, would otherwise have most of its corpus thrown away
  # before anything is fetched.
  #
  # Only genuinely ambiguous URLs are sent, in batches, so a site with ten
  # thousand obvious URLs still costs nothing to classify.
  class Classifier
    BATCH_SIZE = 80

    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[classifications],
      properties: {
        classifications: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[path page_type],
            properties: {
              path: { type: "string" },
              page_type: { type: "string", enum: PageTypes::ALL }
            }
          }
        }
      }
    }.freeze

    def self.build(scan)
      klass = WebsiteIntelligence.live_ai_enabled? ? Live : Fake
      klass.new(scan)
    end

    def initialize(scan, model: Models.fast)
      @scan = scan
      @model = model
    end

    # URLs the rules did not recognise, capped and shallowest-first.
    #
    # A path's depth is a decent proxy for how central the page is: /security
    # matters, /blog/2019/03/a-post-about-a-conference does not. Classifying
    # every unrecognised URL on a large site costs money to label pages the
    # crawl budget was never going to reach.
    def ambiguous
      scan.discovered_urls
          .where("metadata ->> 'confident' = 'false'")
          .order(Arel.sql("length(path) - length(replace(path, '/', '')) ASC, length(path) ASC, id ASC"))
          .limit(WebsiteIntelligence.config.max_classified_urls)
    end

    def refine!
      total = 0

      ambiguous.to_a.each_slice(BATCH_SIZE) do |batch|
        verdicts = classify(batch)
        total += apply(batch, verdicts)
      end

      total
    end

    private
      attr_reader :scan, :model

      def classify(_batch) = raise NotImplementedError

      def apply(batch, verdicts)
        applied = 0

        batch.each do |discovered_url|
          page_type = verdicts[discovered_url.path]
          next if page_type.blank? || page_type == discovered_url.page_type

          discovered_url.update!(
            page_type: page_type,
            corpus_type: PageTypes.corpus_for(page_type),
            priority: Url::Classification::PRIORITIES.fetch(page_type, 20),
            metadata: discovered_url.metadata.merge("reason" => "classified by #{model.id}", "confident" => true)
          )
          applied += 1
        end

        applied
      end
  end
end
