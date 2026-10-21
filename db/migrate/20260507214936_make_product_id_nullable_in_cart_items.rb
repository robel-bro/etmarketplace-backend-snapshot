class MakeProductIdNullableInCartItems < ActiveRecord::Migration[8.1]
  def change
    change_column_null :cart_items, :product_id, true
  end
end
