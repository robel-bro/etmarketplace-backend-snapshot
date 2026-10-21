class AddDeliveryPinToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :delivery_pin, :string
  end
end
