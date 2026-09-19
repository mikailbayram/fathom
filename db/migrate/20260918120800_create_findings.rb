class CreateFindings < ActiveRecord::Migration[8.1]
  def change
    create_table :findings do |t|
      t.references :claim, null: false, foreign_key: true, index: { unique: true }
      t.references :scan, null: false, foreign_key: true

      # Two different things are worth telling a salesperson. A company can bury
      # a fact, or never publish it at all. A site with no documentation
      # produces no buried facts, and "they answer none of this anywhere" is the
      # more useful finding of the two.
      t.string :kind, null: false, default: "buried"
      t.string :topic

      t.text :answer
      t.text :buyer_visible_answer
      t.text :why_it_matters

      t.float :answer_confidence, null: false, default: 0.0
      t.float :buyer_importance, null: false, default: 0.0

      t.float :full_corpus_confidence, null: false, default: 0.0
      t.float :buyer_visible_confidence, null: false, default: 0.0

      t.float :discoverability_score, null: false, default: 0.0
      t.integer :friction_score, null: false, default: 0

      t.string :source_depth
      t.string :source_type

      t.string :status, null: false, default: "pending"

      # Every component of the deterministic score, so the scoring rules stay
      # auditable while the thresholds are still being tuned.
      t.jsonb :score_breakdown, null: false, default: {}

      t.timestamps
    end

    add_index :findings, [ :scan_id, :friction_score ]
    add_index :findings, [ :scan_id, :status ]
    add_index :findings, [ :scan_id, :kind ]
  end
end
