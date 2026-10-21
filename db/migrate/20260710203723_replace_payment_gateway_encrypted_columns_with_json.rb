class ReplacePaymentGatewayEncryptedColumnsWithJson < ActiveRecord::Migration[8.1]
  def change
    # Remove old columns (if they exist)
    remove_column :payment_gateways, :encrypted_private_key, :text if column_exists?(:payment_gateways, :encrypted_private_key)
    remove_column :payment_gateways, :encrypted_public_key, :text if column_exists?(:payment_gateways, :encrypted_public_key)
    remove_column :payment_gateways, :encrypted_fabric_app_id, :text if column_exists?(:payment_gateways, :encrypted_fabric_app_id)
    remove_column :payment_gateways, :encrypted_fabric_app_secret, :text if column_exists?(:payment_gateways, :encrypted_fabric_app_secret)
    remove_column :payment_gateways, :encrypted_merchant_app_id, :text if column_exists?(:payment_gateways, :encrypted_merchant_app_id)

    # Also remove the plain columns that were just renamed (if they exist)
    remove_column :payment_gateways, :private_key, :text if column_exists?(:payment_gateways, :private_key)
    remove_column :payment_gateways, :public_key, :text if column_exists?(:payment_gateways, :public_key)
    remove_column :payment_gateways, :fabric_app_id, :text if column_exists?(:payment_gateways, :fabric_app_id)
    remove_column :payment_gateways, :fabric_app_secret, :text if column_exists?(:payment_gateways, :fabric_app_secret)
    remove_column :payment_gateways, :merchant_app_id, :text if column_exists?(:payment_gateways, :merchant_app_id)

    # Add a single JSON column for gateway credentials
    add_column :payment_gateways, :credentials_json, :jsonb, default: {}
  end
end