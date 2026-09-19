class CreateAIUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_usages do |t|
      t.references :scan, foreign_key: true
      t.references :conversation, foreign_key: true

      t.string :operation, null: false
      t.string :provider, null: false
      t.string :model, null: false

      t.integer :input_tokens
      t.integer :output_tokens

      # Left null when the provider does not report a cost. Unknown is not zero.
      t.decimal :estimated_cost, precision: 12, scale: 6
      t.integer :duration_ms

      t.datetime :created_at, null: false
    end

    add_index :ai_usages, [ :scan_id, :created_at ]
    add_index :ai_usages, :created_at
  end
end
