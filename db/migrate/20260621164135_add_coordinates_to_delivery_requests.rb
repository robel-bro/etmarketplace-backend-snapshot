class AddCoordinatesToDeliveryRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :delivery_requests, :pickup_lat, :decimal
    add_column :delivery_requests, :pickup_lng, :decimal
    add_column :delivery_requests, :delivery_lat, :decimal
    add_column :delivery_requests, :delivery_lng, :decimal
  end
end
