class CreatePages < ActiveRecord::Migration[8.1]
  def change
    create_table :pages do |t|
      t.references :scan, null: false, foreign_key: true
      t.references :discovered_url, null: false, foreign_key: true

      t.text :url, null: false
      t.text :canonical_url, null: false
      t.string :title

      t.string :page_type, null: false, default: "other"
      t.string :corpus_type, null: false, default: "unknown"

      t.text :content
      t.string :content_hash, null: false

      t.integer :http_status
      t.integer :word_count, null: false, default: 0

      t.boolean :indexed, null: false, default: false

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :pages, [ :scan_id, :canonical_url ], unique: true
    # Two URLs serving byte-identical content are one page, not two.
    add_index :pages, [ :scan_id, :content_hash ], unique: true
    add_index :pages, [ :scan_id, :corpus_type ]
  end
end
