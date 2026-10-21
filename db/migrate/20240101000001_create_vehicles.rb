class CreateVehicles < ActiveRecord::Migration[8.1]
  def change
    create_table :vehicles do |t|
      t.references :logistics_partner, null: false, foreign_key: true
      t.string :vehicle_type, null: false   # motorcycle, car, van, truck
      t.string :plate_number
      t.decimal :max_weight_kg, precision: 8, scale: 2   # max payload
      t.decimal :length_cm, :width_cm, :height_cm, precision: 7, scale: 2  # cargo dimensions
      t.boolean :refrigerated, default: false
      t.boolean :fragile_capable, default: false
      t.string :status, default: 'available'   # available, busy, maintenance
      t.timestamps
    end
  end
end