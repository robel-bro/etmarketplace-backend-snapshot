class AddCoordinatesToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :business_lat, :decimal, precision: 10, scale: 6
    add_column :vendors, :business_lng, :decimal, precision: 10, scale: 6
  end
end
