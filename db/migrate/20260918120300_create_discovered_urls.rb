class CreateDiscoveredUrls < ActiveRecord::Migration[8.1]
  def change
    create_table :discovered_urls do |t|
      t.references :scan, null: false, foreign_key: true

      t.text :url, null: false
      t.text :canonical_url, null: false
      t.string :host, null: false
      t.text :path, null: false

      t.string :source, null: false
      t.string :page_type, null: false, default: "other"
      t.string :corpus_type, null: false, default: "unknown"
      t.integer :priority, null: false, default: 0
      t.boolean :selected_for_crawl, null: false, default: false

      # Recording the attempt, not just the result, is what lets the crawl stage
      # resume after a failure without refetching what it already has.
      t.datetime :crawled_at
      t.string :crawl_error

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    # The mapping stage deduplicates on the canonical URL, so the database
    # enforces the same invariant the normalizer promises.
    add_index :discovered_urls, [ :scan_id, :canonical_url ], unique: true
    add_index :discovered_urls, [ :scan_id, :selected_for_crawl ]
    add_index :discovered_urls, [ :scan_id, :priority ]
    add_index :discovered_urls, [ :scan_id, :crawled_at ]
  end
end
