class CreateHandoffs < ActiveRecord::Migration[8.1]
  def change
    # When the corpus cannot answer, the question is worth more than the
    # apology: it is a real enterprise buyer telling you what they need to know
    # and what the website fails to say.
    create_table :handoffs do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :chatbot, null: false, foreign_key: true

      t.text :question, null: false
      t.string :visitor_email
      t.string :status, null: false, default: "waiting"

      t.text :answer
      t.datetime :answered_at

      t.timestamps
    end

    add_index :handoffs, [ :chatbot_id, :status ]
  end
end
