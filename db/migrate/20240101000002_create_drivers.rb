class CreateDrivers < ActiveRecord::Migration[8.1]
  def change
    create_table :drivers do |t|
      t.references :logistics_partner, null: false, foreign_key: true
      t.references :vehicle, foreign_key: true   # currently assigned vehicle (optional)
      t.string :name, null: false
      t.string :phone, null: false
      t.string :license_number
      t.string :status, default: 'offline'        # offline, online, on_delivery
      t.decimal :current_lat, :current_lng, precision: 10, scale: 6
      t.timestamp :location_updated_at
      t.timestamps
    end
  end
end