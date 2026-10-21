class AddAddressAliasesToDeliveryRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :delivery_requests, :delivery_address_lat, :decimal, precision: 10, scale: 6 unless column_exists?(:delivery_requests, :delivery_address_lat)
    add_column :delivery_requests, :delivery_address_lng, :decimal, precision: 10, scale: 6 unless column_exists?(:delivery_requests, :delivery_address_lng)
  end

  def down
    remove_column :delivery_requests, :delivery_address_lat if column_exists?(:delivery_requests, :delivery_address_lat)
    remove_column :delivery_requests, :delivery_address_lng if column_exists?(:delivery_requests, :delivery_address_lng)
  end
end