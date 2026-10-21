class CreateShippingRates < ActiveRecord::Migration[8.1]
  def change
    create_table :shipping_rates do |t|
      t.references :region, null: false, foreign_key: true
      t.references :zone, null: true, foreign_key: true
      t.references :woreda, null: true, foreign_key: true
      t.decimal :standard_rate, precision: 10, scale: 2, default: 0
      t.decimal :express_rate, precision: 10, scale: 2, default: 0
      t.integer :standard_days
      t.integer :express_days

      t.timestamps
    end
    add_index :shipping_rates, [:region_id, :zone_id, :woreda_id], unique: true, name: 'index_shipping_rates_on_region_zone_woreda'
  end
end
