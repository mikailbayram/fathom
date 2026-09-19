# A retrievable slice of a page. Provenance travels with the chunk so a finding
# can always be traced back to the public URL it came from.
class Chunk < ApplicationRecord
  has_neighbors :embedding, normalize: true

  belongs_to :page
  belongs_to :scan
  has_many :finding_sources, dependent: :destroy

  enum :corpus_type, CorpusTypes::ALL.index_by(&:itself), validate: true, prefix: true

  validates :content, presence: true

  scope :embedded, -> { where.not(embedded_at: nil) }
  scope :pending_embedding, -> { where(embedded_at: nil) }
  scope :in_corpus, ->(corpus) { corpus.nil? ? all : where(corpus_type: corpus) }

  # The passage as the company wrote it. `content` additionally carries a
  # context line naming the page and section, which helps retrieval find the
  # chunk but must never end up quoted back to a reader as if it were prose.
  def body
    context = metadata["context"]
    return content if context.blank?

    content.delete_prefix("#{context}\n\n")
  end

  def source_url = metadata["url"]
  def source_title = metadata["title"]
  def heading = metadata["heading"]
  def page_type = metadata["page_type"]

  # A short, evidence-focused excerpt for the UI. Never the whole chunk.
  def excerpt(limit: 320)
    body.squish.truncate(limit, separator: " ")
  end
end
