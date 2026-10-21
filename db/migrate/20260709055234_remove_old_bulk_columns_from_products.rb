class RemoveOldBulkColumnsFromProducts < ActiveRecord::Migration[8.1]
  def change
    remove_column :products, :max_orders_per_day, :integer if column_exists?(:products, :max_orders_per_day)
    remove_column :products, :maximum_bulk_quantity, :integer if column_exists?(:products, :maximum_bulk_quantity)
  end
end