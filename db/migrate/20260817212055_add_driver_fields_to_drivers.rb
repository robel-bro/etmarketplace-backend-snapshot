class AddDriverFieldsToDrivers < ActiveRecord::Migration[8.1]
  def change
    add_column :drivers, :license_number, :string, if_not_exists: true
    add_column :drivers, :address, :string, if_not_exists: true
  end
end