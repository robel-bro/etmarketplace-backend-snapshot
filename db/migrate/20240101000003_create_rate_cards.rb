class CreateRateCards < ActiveRecord::Migration[8.1]
  def change
    create_table :rate_cards do |t|
      t.references :logistics_partner, null: false, foreign_key: true
      t.string :vehicle_type, null: false
      t.decimal :base_rate, precision: 10, scale: 2, default: 50
      t.decimal :per_km_rate, precision: 10, scale: 2, default: 15
      t.decimal :min_charge, precision: 10, scale: 2, default: 100
      t.decimal :weight_surcharge_per_kg_above_5kg, precision: 10, scale: 2, default: 2
      t.decimal :express_surcharge_percent, precision: 5, scale: 2, default: 30.0
      t.decimal :fragile_surcharge, precision: 10, scale: 2, default: 50
      t.timestamps
    end
    add_index :rate_cards, [:logistics_partner_id, :vehicle_type], unique: true
  end
end