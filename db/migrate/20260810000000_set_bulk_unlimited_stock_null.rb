class SetBulkUnlimitedStockNull < ActiveRecord::Migration[8.1]
  def up
    # Bulk products with stock = 0 (or NULL already) are unlimited
    Product.where(bulk_enabled: true, stock: 0).update_all(stock: nil)
    # (Optional) also enforce that all future bulk unlimited products have NULL
    # but the application code already sets nil when bulk_enabled and no stock given
  end

  def down
    # Not reversible – we don't want to put 0 back
    raise ActiveRecord::IrreversibleMigration
  end
end