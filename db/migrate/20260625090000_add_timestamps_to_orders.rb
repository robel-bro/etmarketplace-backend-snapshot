class AddTimestampsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :shipped_at, :datetime
    add_column :orders, :paid_at, :datetime
  end
end