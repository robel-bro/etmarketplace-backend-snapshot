class AddVehicleToDeliveryRequests < ActiveRecord::Migration[8.1]
  def change
    add_reference :delivery_requests, :vehicle, foreign_key: true
  end
end