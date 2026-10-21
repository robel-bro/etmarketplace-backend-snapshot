class AddTelebirrFieldsToPaymentGatewayConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_gateways, :encrypted_private_key, :text
    add_column :payment_gateways, :encrypted_public_key,  :text
    add_column :payment_gateways, :encrypted_fabric_app_id, :text
    add_column :payment_gateways, :encrypted_fabric_app_secret, :text
    add_column :payment_gateways, :encrypted_merchant_app_id, :text

    # Ensure the config column is jsonb (if not already)
    change_column :payment_gateways, :config, :jsonb, using: 'config::jsonb' unless column_exists?(:payment_gateways, :config, :jsonb)
  end
end