class CreateFindingSources < ActiveRecord::Migration[8.1]
  def change
    create_table :finding_sources do |t|
      t.references :finding, null: false, foreign_key: true
      t.references :chunk, null: false, foreign_key: true

      t.float :relevance_score, null: false, default: 0.0
      t.boolean :is_primary, null: false, default: false
      t.text :quoted_excerpt

      t.string :corpus_type, null: false, default: "deep"

      t.timestamps
    end

    add_index :finding_sources, [ :finding_id, :chunk_id ], unique: true
  end
end
