class AddPerformanceIndexes < ActiveRecord::Migration[7.0]
  def change
    add_column :vendors, :products_count, :integer, default: 0, null: false
    add_column :vendors, :total_sales_count_cache, :integer, default: 0, null: false

    add_index :line_items, [:product_id, :order_id], name: "index_line_items_on_product_id_and_order_id", if_not_exists: true
    add_index :orders, :created_at, if_not_exists: true

    # Backfill counter caches manually – no model dependency
    Vendor.find_each do |v|
      count = v.products.count
      sales = v.products.sum(:sold_count) || 0
      v.update_columns(products_count: count, total_sales_count_cache: sales)
    end
  end
end