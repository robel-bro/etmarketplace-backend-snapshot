class AddServiceLevelToDeliveryRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :delivery_requests, :service_level, :integer, default: 0, null: false
  end
end