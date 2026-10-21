class FixCartItemUniqueIndex < ActiveRecord::Migration[8.1]
  def up
    # Remove the old unique constraint that blocked multiple variants
    if index_exists?(:cart_items, [:cart_id, :product_id], unique: true)
      remove_index :cart_items, column: [:cart_id, :product_id]
    end

    # Add a non‑unique index for fast lookups (optional, but recommended)
    unless index_exists?(:cart_items, [:cart_id, :product_id])
      add_index :cart_items, [:cart_id, :product_id]
    end
  end

  def down
    # Restore the original unique index (if you ever need to rollback)
    if index_exists?(:cart_items, [:cart_id, :product_id])
      remove_index :cart_items, column: [:cart_id, :product_id]
    end
    unless index_exists?(:cart_items, [:cart_id, :product_id], unique: true)
      add_index :cart_items, [:cart_id, :product_id], unique: true
    end
  end
end
