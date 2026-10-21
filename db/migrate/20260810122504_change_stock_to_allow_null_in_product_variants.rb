class ChangeStockToAllowNullInProductVariants < ActiveRecord::Migration[8.1]
  def change
    change_column_null :product_variants, :stock, true
  end
end