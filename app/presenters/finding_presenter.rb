# frozen_string_literal: true

# Shapes a finding and its evidence for the React pages.
#
# Generated interpretation and quoted source material are kept in separate
# fields so the UI can keep them visually separate -- a reader has to be able to
# tell what the company published from what we concluded.
class FindingPresenter
  def initialize(finding)
    @finding = finding
  end

  def row
    {
      id: finding.id,
      kind: finding.kind,
      score: finding.friction_score,
      category: finding.category,
      category_label: finding.category_label,
      question: finding.claim.question_text,
      topic: finding.claim.topic,
      answer: finding.answer,
      buyer_importance_label: finding.buyer_importance_label,
      answer_confidence: percent(finding.full_corpus_confidence),
      buyer_visible_confidence: percent(finding.buyer_visible_confidence),
      discoverability_gap: finding.discoverability_gap_points,
      source_type: finding.source_type,
      source_type_label: PageTypes.label(finding.source_type),
      primary_source: source(finding.primary_source)
    }
  end

  def detail
    row.merge(
      why_it_matters: finding.why_it_matters,
      buyer_visible_answer: finding.buyer_visible_answer,
      buyer_visible_answerable: finding.buyer_visible_answer.present?,
      supporting_sources: finding.supporting_sources.map { |finding_source| source(finding_source) },
      lead: {
        id: finding.scan.lead_id,
        company: finding.scan.lead.name,
        domain: finding.scan.domain
      }
    )
  end

  private
    attr_reader :finding

    def source(finding_source)
      return nil if finding_source.nil?

      chunk = finding_source.chunk
      {
        title: chunk.source_title.presence || chunk.heading.presence || "Source",
        url: chunk.source_url,
        host: chunk.metadata["host"],
        page_type: chunk.page_type,
        page_type_label: PageTypes.label(chunk.page_type),
        corpus_type: finding_source.corpus_type,
        corpus_label: CorpusTypes.label(finding_source.corpus_type),
        excerpt: finding_source.quoted_excerpt
      }
    end

    def percent(value) = (value.to_f * 100).round.clamp(0, 100)
end
