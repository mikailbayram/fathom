class CreateChatbots < ActiveRecord::Migration[8.1]
  def change
    create_table :chatbots do |t|
      t.references :scan, null: false, foreign_key: true, index: { unique: true }

      t.string :name, null: false
      t.string :slug, null: false
      t.string :status, null: false, default: "active"
      t.boolean :public, null: false, default: true

      t.text :system_prompt

      t.timestamps
    end

    add_index :chatbots, :slug, unique: true
  end
end
