class RemoveDefaultFromCartItemsQuantity < ActiveRecord::Migration[8.1]
  def change
    change_column_default :cart_items, :quantity, nil
  end
end
