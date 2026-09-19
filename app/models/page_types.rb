# The vocabulary shared by URL classification, crawl planning, relevance
# filtering and corpus assignment.
module PageTypes
  ALL = %w[
    homepage marketing product solution pricing security trust integration
    docs developer_docs help_center support legal pdf blog news careers other
  ].freeze

  # Content an enterprise buyer meets on the primary marketing journey.
  BUYER_VISIBLE = %w[homepage marketing product solution pricing security integration].freeze

  # Public, but commonly several clicks deeper than anyone browses.
  DEEP = %w[docs developer_docs help_center support trust pdf legal].freeze

  HIGH_VALUE = %w[
    docs developer_docs security trust pricing integration support help_center
    product solution pdf
  ].freeze
  MEDIUM_VALUE = %w[marketing legal homepage].freeze
  LOW_VALUE = %w[blog news careers other].freeze

  def self.corpus_for(page_type)
    page_type = page_type.to_s
    return CorpusTypes::BUYER_VISIBLE if BUYER_VISIBLE.include?(page_type)
    return CorpusTypes::DEEP if DEEP.include?(page_type)

    CorpusTypes::IGNORED
  end

  def self.relevance(page_type)
    page_type = page_type.to_s
    return :high if HIGH_VALUE.include?(page_type)
    return :medium if MEDIUM_VALUE.include?(page_type)

    :low
  end

  # Low-relevance pages are crawled for context but never embedded: a blog
  # archive is not where an enterprise answer hides, and embedding it costs
  # money and dilutes retrieval.
  def self.indexable = (HIGH_VALUE + MEDIUM_VALUE).freeze

  def self.indexable?(page_type) = indexable.include?(page_type.to_s)

  def self.label(page_type)
    case page_type.to_s
    when "developer_docs" then "Developer documentation"
    when "docs" then "Documentation"
    when "help_center" then "Help center"
    when "pdf" then "PDF document"
    when "trust" then "Trust center"
    else page_type.to_s.humanize
    end
  end
end
