# The grounded RAG assistant created automatically for every completed scan,
# backed by exactly that scan's indexed corpus and nothing else.
class Chatbot < ApplicationRecord
  STATUSES = %w[active disabled].freeze

  belongs_to :scan
  has_many :conversations, dependent: :destroy
  has_many :handoffs, dependent: :destroy
  has_one :company_profile, through: :scan

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true

  delegate :lead, to: :scan
  delegate :domain, to: :lead

  scope :publicly_shared, -> { where(public: true, status: :active) }

  def self.generate_slug(domain)
    base = domain.to_s.split(".").first.to_s.parameterize.presence || "demo"
    # The suffix is random, not derived: a public demo link should not be
    # guessable from the company's domain alone.
    "#{base}-#{SecureRandom.hex(3)}"
  end

  def publicly_shared? = public? && active?

  # The findings a salesperson would actually want a lead to ask about.
  def suggested_questions(limit: 4)
    scan.findings.viable.ranked.limit(limit).includes(:claim).map { |finding| finding.claim.question_text }
  end
end
