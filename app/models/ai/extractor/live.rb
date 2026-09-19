# frozen_string_literal: true

module AI
  class Extractor
    # Extraction through the configured analysis model.
    class Live < Extractor
      def extract(batch)
        response = Client.new(model: model, operation: "claim_extraction", scan: scan).structured(
          schema: SCHEMA,
          instructions: <<~TEXT,
            You read a company's public content and extract the specific, checkable
            statements a serious buyer would evaluate on.

            #{Prompts::GROUNDING_RULES}

            What matters differs by industry, and you should judge it from what this
            company actually sells rather than from any fixed list. For a software vendor
            it is plan restrictions, limits, retention periods, supported and unsupported
            capabilities, recovery objectives, failure behaviour. For a manufacturer it is
            tolerances, materials, capacities, lead times, certifications, compatible
            equipment, minimum orders. For a services firm it is scope, timelines, team
            composition, what is and is not included. Extract whichever of these the
            passage actually states.

            Extract a claim only when the passage states something concrete a buyer could
            hold them to -- a number, a limit, a standard, a named capability, an explicit
            exclusion. Skip positioning, restatements of the obvious, and anything that is
            merely a heading or a navigation list. A passage may yield no claims at all;
            that is a normal and useful answer. Never write a statement the passage does
            not support, and use the company's own terms rather than paraphrasing into
            generic language.

            For each claim also write the buyer question that statement answers.
          TEXT
          prompt: <<~TEXT
            Company: #{company} (#{scan.domain})
            What they sell: #{scan.company_profile&.product_category.presence || "unknown"}
            #{"Their own content raises: #{Array(scan.company_profile&.enterprise_concerns).first(8).join(', ')}" if scan.company_profile&.enterprise_concerns.present?}

            #{Prompts.untrusted_material(batch.map { |chunk| Corpus::Candidate.new(chunk: chunk) })}

            Extract the checkable enterprise claims. Cite the id of the source passage.
          TEXT
        )

        chunks = batch.index_by(&:id)

        Array(response["claims"]).filter_map do |row|
          chunk = chunks[row["chunk_id"].to_i]
          next if chunk.nil? || row["statement"].blank? || row["question"].blank?

          Claim.new(
            chunk_id: chunk.id,
            statement: row["statement"],
            question: row["question"],
            category: ::Claim::CATEGORIES.include?(row["category"]) ? row["category"] : "security_compliance",
            importance: row["importance"].to_f.clamp(0.0, 1.0),
            topic: Lexicon.concerns_in(row["statement"]).first,
            # Verified against the passage rather than taken on trust.
            support: support_for(row["statement"], chunk)
          )
        end
      end
    end
  end
end
