# db/migrate/20260730_create_address_caches.rb
class CreateAddressCaches < ActiveRecord::Migration[8.1]
  def change
    create_table :address_caches do |t|
      t.string  :raw_address,        null: false, index: { unique: true }
      t.decimal :latitude,  precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.string  :formatted_address
      t.string  :city
      t.string  :subcity
      t.string  :woreda
      t.string  :street
      t.string  :landmark
      t.string  :source             # "auto" or "manual"
      t.boolean :corrected, default: false  # true if a user manually fixed the pin
      t.integer :count,     default: 1
      t.datetime :last_used_at

      t.timestamps
    end
  end
end