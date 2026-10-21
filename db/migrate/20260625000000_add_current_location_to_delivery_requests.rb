class AddCurrentLocationToDeliveryRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :delivery_requests, :current_lat, :decimal, precision: 10, scale: 6
    add_column :delivery_requests, :current_lng, :decimal, precision: 10, scale: 6
  end
end