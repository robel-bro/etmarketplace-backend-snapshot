class AddBulkLimitsToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :maximum_bulk_quantity, :integer
    add_column :products, :max_orders_per_day, :integer
    add_column :products, :max_quantity_per_day, :integer
  end
end
