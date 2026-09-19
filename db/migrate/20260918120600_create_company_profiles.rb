class CreateCompanyProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :company_profiles do |t|
      t.references :scan, null: false, foreign_key: true, index: { unique: true }

      t.string :company_name
      t.text :description
      t.string :product_category

      t.jsonb :buyer_personas, null: false, default: []
      t.jsonb :products, null: false, default: []
      t.jsonb :integrations, null: false, default: []
      t.jsonb :enterprise_features, null: false, default: []
      t.jsonb :enterprise_concerns, null: false, default: []

      t.jsonb :raw_analysis, null: false, default: {}

      t.timestamps
    end
  end
end
