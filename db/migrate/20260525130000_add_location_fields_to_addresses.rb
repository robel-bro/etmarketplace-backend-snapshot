class AddLocationFieldsToAddresses < ActiveRecord::Migration[8.1]
  def change
    add_column :addresses, :sub_city, :string
    add_column :addresses, :building_name, :string
    add_column :addresses, :latitude, :decimal, precision: 10, scale: 6
    add_column :addresses, :longitude, :decimal, precision: 10, scale: 6
  end
end
