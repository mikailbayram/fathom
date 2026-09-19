# frozen_string_literal: true

# Asks one question of the buyer-visible corpus: does the marketing journey
# establish what the documentation states?
#
# The deep side needs no search -- the claim came from a passage and already
# carries its source. Only the shallow side is an open question, which is why
# this stage costs half what answering twice did.
class CheckClaimVisibilityJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    claim = job.arguments.first
    claim&.update_columns(status: "failed", error_message: "#{error.class}: #{error.message}".truncate(500))
    scan = claim&.scan
    scan.pipeline.advance! if scan && !scan.claims.unresolved.exists?
  end

  def perform(claim)
    scan = claim.scan
    return if claim.checked? || claim.discarded?

    claim.update!(status: "checking")

    # Checked against the statement, not the question. "How does Acme handle
    # webhooks?" is half-answered by a marketing page that merely mentions
    # webhooks; "retried six times with exponential backoff over 24 hours" is
    # not. The question is a label for a human; the statement is the fact we are
    # asking whether a buyer can reach.
    buyer_visible = AI::Answerer.build(scan).answer(claim.statement, scope: :buyer_visible)

    persist(claim, buyer_visible)
    claim.update!(status: "checked")

    scan.pipeline.advance! unless scan.claims.unresolved.exists?
  end

  private
    def persist(claim, buyer_visible)
      Finding.transaction do
        finding = claim.finding || claim.build_finding(scan: claim.scan)
        finding.assign_attributes(
          answer: claim.statement,
          buyer_visible_answer: buyer_visible.answerable? ? buyer_visible.text : nil,
          why_it_matters: why_it_matters(claim, buyer_visible),
          answer_confidence: claim.support,
          buyer_importance: claim.buyer_importance,
          full_corpus_confidence: claim.support,
          buyer_visible_confidence: buyer_visible.coverage,
          status: "pending"
        )
        finding.save!

        # The evidence is the passage the claim came from, not a fresh search.
        finding.finding_sources.delete_all
        next if claim.chunk.nil?

        finding.finding_sources.create!(
          chunk: claim.chunk,
          relevance_score: claim.support,
          is_primary: true,
          corpus_type: claim.chunk.corpus_type,
          quoted_excerpt: claim.chunk.excerpt
        )
      end
    end

    # Written from what actually happened, not generated.
    def why_it_matters(claim, buyer_visible)
      company = claim.scan.lead.name

      if buyer_visible.answerable?
        "#{company} states this on the pages a buyer meets on the primary marketing journey as well as in its deeper public content."
      else
        "#{company} published this in its #{PageTypes.label(claim.chunk&.page_type.to_s).downcase}, but nothing on the " \
          "pages a buyer meets on the primary marketing journey establishes it."
      end
    end
end
