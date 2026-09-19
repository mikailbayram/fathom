# Something the company published in its deep public content, scored by how hard
# it is to reach from the buyer-facing website.
class Finding < ApplicationRecord
  STATUSES = %w[pending viable below_threshold covered].freeze

  belongs_to :claim
  belongs_to :scan
  has_many :finding_sources, -> { order(is_primary: :desc, relevance_score: :desc) },
           dependent: :destroy, inverse_of: :finding
  has_many :chunks, through: :finding_sources

  enum :status, STATUSES.index_by(&:itself), validate: true

  scope :ranked, -> { order(friction_score: :desc, id: :asc) }

  delegate :category, :category_label, :topic, to: :claim

  def primary_source = finding_sources.detect(&:is_primary) || finding_sources.first

  def supporting_sources = finding_sources.reject(&:is_primary)

  # The headline number in the signature comparison. Defined once, by
  # FrictionScore, so the badge and the score can never disagree.
  def discoverability_gap_points = (FrictionScore.new(self).gap * 100).round

  def buyer_importance_label
    case buyer_importance
    when 0.75.. then "High"
    when 0.45...0.75 then "Medium"
    else "Low"
    end
  end
end
