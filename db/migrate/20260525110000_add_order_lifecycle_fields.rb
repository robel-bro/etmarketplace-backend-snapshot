class AddOrderLifecycleFields < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :return_window_days, :integer, default: 7
    add_column :orders, :delivered_at, :datetime
    add_column :orders, :completed_at, :datetime
    add_column :orders, :refunded_amount, :decimal, precision: 10, scale: 2, default: 0
    add_column :orders, :payment_transaction_id, :string
  end
end
