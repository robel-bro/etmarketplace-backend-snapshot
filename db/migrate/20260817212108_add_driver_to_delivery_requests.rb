class AddDriverToDeliveryRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :delivery_requests, :driver_id, :bigint, if_not_exists: true
    add_index :delivery_requests, :driver_id, if_not_exists: true
  end
end