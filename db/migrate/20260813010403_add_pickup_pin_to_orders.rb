class AddPickupPinToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :pickup_pin, :string
  end
end
