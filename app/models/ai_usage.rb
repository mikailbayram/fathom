# Every AI operation the application performs, recorded from day one.
#
# Token counts and costs come from the provider's own usage metadata. When a
# provider reports nothing, the columns stay null: unknown is not zero.
class AIUsage < ApplicationRecord
  # Every operation that reaches a provider. Validated rather than merely
  # listed: nothing referred to this, so it quietly fell out of date -- it was
  # missing claim_extraction and coverage_checklist, and still named a
  # question_generation stage that no longer exists. A list of what the
  # application does that nobody checks is worse than no list, because it reads
  # like one that is true.
  OPERATIONS = %w[
    answer_buyer_visible
    answer_full
    chat_answer
    claim_extraction
    company_analysis
    coverage_checklist
    embedding
    page_classification
  ].freeze

  belongs_to :scan, optional: true
  belongs_to :conversation, optional: true

  validates :operation, :provider, :model, presence: true
  validates :operation, inclusion: { in: OPERATIONS }

  scope :today, -> { where(created_at: Time.current.all_day) }

  # Paid calls the provider never put a price on. Kept separate from the sum
  # because a null cost is not a free call, and summing it as zero is how a
  # budget stops applying without anyone noticing.
  scope :unpriced, -> { where(estimated_cost: nil).where.not(provider: "fake") }

  def self.record(operation:, provider:, model:, scan: nil, conversation: nil,
                  input_tokens: nil, output_tokens: nil, estimated_cost: nil, duration_ms: nil)
    create!(
      operation: operation.to_s,
      provider: provider.to_s,
      model: model.to_s,
      scan: scan,
      conversation: conversation,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      estimated_cost: estimated_cost,
      duration_ms: duration_ms
    )
  end
end
