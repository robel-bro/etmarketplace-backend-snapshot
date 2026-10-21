class AddReturnPolicyColumnsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :restocking_fee_percent, :decimal, precision: 5, scale: 2, default: 0.0 unless column_exists?(:orders, :restocking_fee_percent)
    add_column :orders, :return_shipping_responsibility, :string, default: 'buyer' unless column_exists?(:orders, :return_shipping_responsibility)
  end
end