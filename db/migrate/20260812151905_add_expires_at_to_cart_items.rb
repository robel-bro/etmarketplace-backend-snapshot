class AddExpiresAtToCartItems < ActiveRecord::Migration[8.1]
  def up
    add_column :cart_items, :expires_at, :datetime
    add_index :cart_items, :expires_at
  end

  def down
    remove_index :cart_items, :expires_at
    remove_column :cart_items, :expires_at
  end
end