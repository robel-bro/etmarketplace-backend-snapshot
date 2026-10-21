# db/migrate/20260815150000_add_base_price_to_cart_items.rb

class AddBasePriceToCartItems < ActiveRecord::Migration[8.1]
  def change
    add_column :cart_items, :base_price, :decimal, precision: 10, scale: 2, default: 0.0, null: false
  end
end