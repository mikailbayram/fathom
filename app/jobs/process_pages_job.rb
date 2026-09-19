# frozen_string_literal: true

# Stage four: split the worthwhile pages into chunks with their provenance.
class ProcessPagesJob < PipelineJob
  BATCH_SIZE = 50

  def stage = "processing"

  def perform(scan)
    ensure_mode!(scan)
    index = Corpus::Index.new(scan)
    index.pending_pages.limit(BATCH_SIZE).each { |page| index.chunk(page) }

    if index.chunked?
      advance(scan)
    else
      self.class.perform_later(scan)
    end
  end
end
