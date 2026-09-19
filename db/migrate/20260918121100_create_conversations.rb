class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :chatbot, null: false, foreign_key: true

      # Anonymous visitors are identified by a signed cookie, never an account.
      t.string :session_id, null: false

      t.timestamps
    end

    add_index :conversations, [ :chatbot_id, :session_id ], unique: true
  end
end
