# A specific, checkable statement the company published in its deep public
# content -- and the buyer question that statement answers.
#
# Claims are extracted from what the company actually wrote, so a scan finds the
# things nobody would have thought to ask about. The question text is a label
# derived from the claim, not the thing that drove the search.
class Claim < ApplicationRecord
  CATEGORIES = %w[
    security_compliance
    integrations
    api
    implementation
    migration
    pricing_packaging
    support
    enterprise_controls
    data_governance
    reliability
    specifications
    capacity_and_lead_time
    certifications
    materials_and_standards
    commercial_terms
  ].freeze

  STATUSES = %w[pending checking checked discarded failed].freeze

  # Below this, the source passage does not actually say what the claim says.
  MINIMUM_SUPPORT = 0.4

  belongs_to :scan
  belongs_to :chunk, optional: true
  has_one :finding, dependent: :destroy

  enum :category, CATEGORIES.index_by(&:itself), validate: true, prefix: true
  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :statement, presence: true
  validates :question_text, presence: true
  validates :buyer_importance, numericality: { in: 0.0..1.0 }

  scope :unresolved, -> { where(status: %w[pending checking]) }
  scope :grounded, -> { where(support: MINIMUM_SUPPORT..) }

  alias_attribute :question, :question_text

  def category_label = category.tr("_", " ").upcase

  # The public URL the claim came from, which every finding must be able to show.
  def source_url = chunk&.source_url
end
