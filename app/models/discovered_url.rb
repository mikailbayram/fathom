# The result of the mapping stage: an inventory of public URLs recorded before
# anything is fetched, so the crawl plan is a decision rather than a side effect.
class DiscoveredUrl < ApplicationRecord
  SOURCES = %w[root sitemap internal_link subdomain pdf_link crawler_map].freeze

  belongs_to :scan
  has_many :pages, dependent: :nullify

  enum :source, SOURCES.index_by(&:itself), validate: true, prefix: true
  enum :page_type, PageTypes::ALL.index_by(&:itself), validate: true, prefix: true
  enum :corpus_type, CorpusTypes::ALL.index_by(&:itself), validate: true, prefix: true

  validates :url, :canonical_url, :host, :path, presence: true

  scope :selected, -> { where(selected_for_crawl: true) }
  scope :by_priority, -> { order(priority: :desc, id: :asc) }
end
