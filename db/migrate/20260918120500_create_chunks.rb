class CreateChunks < ActiveRecord::Migration[8.1]
  def change
    dimensions = WebsiteIntelligence.config.ai.embedding_dimensions

    create_table :chunks do |t|
      t.references :page, null: false, foreign_key: true
      # Denormalized from pages so retrieval can scope by scan and corpus
      # without a join on every candidate query.
      t.references :scan, null: false, foreign_key: true
      t.string :corpus_type, null: false, default: "unknown"

      t.text :content, null: false
      t.integer :position, null: false, default: 0
      t.integer :token_count, null: false, default: 0

      t.vector :embedding, limit: dimensions
      t.string :embedding_model
      t.datetime :embedded_at

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :chunks, [ :page_id, :position ], unique: true
    add_index :chunks, [ :scan_id, :corpus_type ]

    # Lexical half of hybrid retrieval. Exact enterprise terminology (SCIM,
    # RPO, NetSuite) is what vector similarity is worst at.
    execute <<~SQL
      ALTER TABLE chunks
      ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
    SQL
    execute "CREATE INDEX index_chunks_on_search_vector ON chunks USING gin (search_vector)"

    # HNSW supports at most 2000 dimensions; wider models fall back to an exact
    # scan, which is correct if slower.
    if dimensions <= 2000
      execute "CREATE INDEX index_chunks_on_embedding ON chunks USING hnsw (embedding vector_cosine_ops)"
    end
  end
end
