class AddRequiredVehicleTypeToDeliveryRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :delivery_requests, :required_vehicle_type, :string
  end
end
