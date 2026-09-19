# The evidence behind a finding: which chunk supported it, and the short quote
# a reader can check against the original public page.
class FindingSource < ApplicationRecord
  belongs_to :finding
  belongs_to :chunk

  enum :corpus_type, CorpusTypes::ALL.index_by(&:itself), validate: true, prefix: true

  delegate :source_url, :source_title, :page_type, to: :chunk
end
