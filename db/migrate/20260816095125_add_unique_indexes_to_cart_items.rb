class AddUniqueIndexesToCartItems < ActiveRecord::Migration[8.1]
  def change
    # Unique product+variant per cart
    add_index :cart_items,
              [:cart_id, :product_id, :variant_attributes],
              unique: true,
              where: "package_id IS NULL",
              name: 'index_cart_items_on_cart_product_variant_unique'

    # Unique package per cart
    add_index :cart_items,
              [:cart_id, :package_id],
              unique: true,
              where: "product_id IS NULL",
              name: 'index_cart_items_on_cart_package_unique'
  end
end