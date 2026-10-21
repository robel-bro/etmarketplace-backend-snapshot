class AddCodStatusToDeliveryRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :delivery_requests, :cod_status, :integer, default: 0, null: false
    add_index :delivery_requests, :cod_status
  end
end