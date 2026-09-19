# A crawled public page, PDF or documentation article.
class Page < ApplicationRecord
  belongs_to :scan
  belongs_to :discovered_url
  has_many :chunks, -> { order(:position) }, dependent: :delete_all, inverse_of: :page

  enum :page_type, PageTypes::ALL.index_by(&:itself), validate: true, prefix: true
  enum :corpus_type, CorpusTypes::ALL.index_by(&:itself), validate: true, prefix: true

  validates :url, :canonical_url, :content_hash, presence: true

  scope :indexed, -> { where(indexed: true) }
  scope :worth_indexing, -> { where(page_type: PageTypes.indexable) }

  def host = URI.parse(canonical_url).host
rescue URI::InvalidURIError
  nil
end
