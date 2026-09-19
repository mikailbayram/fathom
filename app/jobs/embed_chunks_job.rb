# frozen_string_literal: true

# Stage five: embed the chunks in batches.
class EmbedChunksJob < PipelineJob
  BATCHES_PER_RUN = 10

  def stage = "embedding"

  def perform(scan)
    ensure_mode!(scan)
    index = Corpus::Index.new(scan)
    BATCHES_PER_RUN.times { break if index.embed_batch.zero? }

    if index.embedded?
      advance(scan)
    else
      self.class.perform_later(scan)
    end
  end
end
