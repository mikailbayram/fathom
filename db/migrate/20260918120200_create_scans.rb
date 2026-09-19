class CreateScans < ActiveRecord::Migration[8.1]
  def change
    create_table :scans do |t|
      t.references :lead, null: false, foreign_key: true

      t.string :status, null: false, default: "pending"
      # The mode the scan actually ran in, so a fake scan is never mistaken for
      # a live one when reading results later.
      t.string :mode, null: false, default: "fake"

      t.integer :urls_discovered, null: false, default: 0
      t.integer :pages_selected, null: false, default: 0
      t.integer :pages_crawled, null: false, default: 0
      t.integer :pages_indexed, null: false, default: 0
      t.integer :chunks_count, null: false, default: 0
      t.integer :claims_count, null: false, default: 0
      t.integer :findings_count, null: false, default: 0

      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.string :failed_stage
      t.text :error_message

      # Stage markers, each of which tells "this stage found nothing" apart from
      # "this stage has not run yet" -- a distinction the pipeline depends on,
      # because an empty result is a legitimate outcome for all three.
      t.datetime :urls_classified_at
      t.datetime :claims_extracted_at
      t.datetime :coverage_audited_at

      t.jsonb :plan_summary, null: false, default: {}

      t.timestamps
    end

    add_index :scans, [ :lead_id, :created_at ]
    add_index :scans, :status
  end
end
