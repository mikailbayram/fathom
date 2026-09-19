class CreateLeads < ActiveRecord::Migration[8.1]
  def change
    # One lead is one project: the company, its scans, its gaps and its demo all
    # live under a single record, so the domain language matches the product.
    create_table :leads do |t|
      t.string :name, null: false
      t.string :domain, null: false
      t.string :website_url, null: false

      t.timestamps
    end

    add_index :leads, :domain, unique: true
  end
end
