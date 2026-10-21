class CreateReturnPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :return_policies do |t|
      t.string :name, null: false
      t.integer :return_window_days, null: false, default: 7
      t.decimal :restocking_fee_percent, precision: 5, scale: 2, default: 0.0
      t.string :return_shipping_responsibility, default: 'buyer'   # buyer, seller, platform
      t.text :description
      t.boolean :is_active, default: true
      t.jsonb :applicable_categories, default: []     # array of category IDs
      t.jsonb :excluded_categories, default: []       # never returnable
      t.timestamps
    end
  end
end