class AddDriverFieldsToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :driver_name, :string
    add_column :vehicles, :driver_phone, :string
  end
end