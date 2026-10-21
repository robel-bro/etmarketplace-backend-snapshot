class AddIndexesForFilterPerformance < ActiveRecord::Migration[8.1]
  def change
    add_index :products, :rating unless index_exists?(:products, :rating)
    add_index :products, :free_shipping unless index_exists?(:products, :free_shipping)
    add_index :products, :seller_pays_shipping unless index_exists?(:products, :seller_pays_shipping)
    add_index :products, [:seller_pays_shipping, :shipping_subsidy_type, :shipping_subsidy_value],
      name: 'idx_products_delivery_fields'
  end
end
