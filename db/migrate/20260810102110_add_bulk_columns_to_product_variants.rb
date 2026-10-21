class AddBulkColumnsToProductVariants < ActiveRecord::Migration[8.1]
  def change
    add_column :product_variants, :unlimited_stock, :boolean
    add_column :product_variants, :minimum_bulk_quantity, :integer
  end
end
