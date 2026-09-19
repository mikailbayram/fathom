# frozen_string_literal: true

module Corpus
  # Stage four: turn crawled pages into the retrievable, embedded corpus.
  #
  #   index = Corpus::Index.new(scan)
  #   index.chunk(page)
  #   index.embed_batch
  #
  # Not every crawled page is embedded. A careers listing is fetched for the
  # record and then left alone: embedding it costs money and dilutes retrieval
  # without ever holding an enterprise answer.
  class Index
    def initialize(scan, embedder: nil)
      @scan = scan
      @embedder = embedder || AI::Embedder.build(scan: scan)
    end

    def pending_pages = scan.pages.worth_indexing.where(indexed: false)

    def chunked? = !pending_pages.exists?

    def chunk(page)
      pieces = Chunker.new(page).pieces

      Chunk.transaction do
        # destroy rather than delete: a rerun must take the cited evidence with
        # the chunk it cited, not leave a finding pointing at nothing.
        page.chunks.destroy_all

        rows = pieces.map do |piece|
          piece.to_attributes.merge(
            page_id: page.id,
            scan_id: scan.id,
            corpus_type: page.corpus_type,
            created_at: Time.current,
            updated_at: Time.current
          )
        end

        Chunk.insert_all!(rows) if rows.any?
        page.update!(indexed: true)
      end

      page.chunks.reset
      scan.chunks.reset

      refresh_counters
      pieces.size
    end

    def pending_embedding = scan.chunks.pending_embedding

    def embedded? = !pending_embedding.exists?

    # Embeds one batch and returns how many chunks it handled, so a job can
    # loop until zero without ever holding the whole corpus in memory.
    def embed_batch(size: nil)
      size ||= WebsiteIntelligence.config.embedding_batch_size
      batch = pending_embedding.order(:id).limit(size).to_a
      return 0 if batch.empty?

      vectors = embedder.embed(batch.map(&:content))
      now = Time.current

      Chunk.transaction do
        batch.each_with_index do |chunk, position|
          chunk.update_columns(
            embedding: vectors[position],
            embedding_model: embedder.model.id,
            embedded_at: now,
            updated_at: now
          )
        end
      end

      refresh_counters
      batch.size
    end

    private
      attr_reader :scan, :embedder

      def refresh_counters
        scan.update_columns(
          pages_indexed: scan.pages.indexed.count,
          chunks_count: scan.chunks.count,
          updated_at: Time.current
        )
        scan.broadcast_status!
      end
  end
end
