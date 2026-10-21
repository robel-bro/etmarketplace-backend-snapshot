class AddProductCardFieldsToProducts < ActiveRecord::Migration[8.0]
  def change
    # Only add columns if they don't already exist
    add_column :products, :original_price, :decimal, precision: 10, scale: 2 unless column_exists?(:products, :original_price)
    add_column :products, :rating, :decimal, precision: 2, scale: 1, default: 0.0 unless column_exists?(:products, :rating)
    add_column :products, :reviews_count, :integer, default: 0 unless column_exists?(:products, :reviews_count)
    add_column :products, :sold_count, :integer, default: 0 unless column_exists?(:products, :sold_count)
    add_column :products, :free_shipping, :boolean, default: false unless column_exists?(:products, :free_shipping)
    add_column :products, :discount, :integer, default: 0 unless column_exists?(:products, :discount)
  end
end
