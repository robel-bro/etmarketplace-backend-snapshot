class AddPriceToCartItems < ActiveRecord::Migration[8.1]
  def change
    add_column :cart_items, :price, :decimal, precision: 10, scale: 2
  end
end
