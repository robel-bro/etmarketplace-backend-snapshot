class AddMissingFinancialColumnsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :service_fee, :decimal, precision: 10, scale: 2, default: 0.0
    add_column :orders, :vat_amount, :decimal, precision: 10, scale: 2, default: 0.0
  end
end