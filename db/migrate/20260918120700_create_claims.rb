class CreateClaims < ActiveRecord::Migration[8.1]
  def change
    # Gaps are driven by what the company actually published, not by a fixed
    # list of questions we thought to ask. The record is a claim extracted from
    # deep content; the question it answers is a label derived from it.
    create_table :claims do |t|
      t.references :scan, null: false, foreign_key: true
      # The passage the claim came from. A claim with no source is not a claim.
      t.references :chunk, foreign_key: true, index: true

      t.string :category, null: false, default: "security_compliance"
      t.text :statement
      t.text :question_text, null: false
      t.string :topic

      # 0.0-1.0 as judged by the analysis model; scoring converts it to points.
      t.float :buyer_importance, null: false, default: 0.5
      # How well the source passage backs the statement. Extraction discards
      # anything the passage does not actually establish.
      t.float :support, null: false, default: 0.0

      t.string :status, null: false, default: "pending"
      t.text :error_message

      t.timestamps
    end

    add_index :claims, [ :scan_id, :status ]
    add_index :claims, [ :scan_id, :category ]
    add_index :claims, [ :scan_id, :statement ], unique: true, length: { statement: 180 }
  end
end
