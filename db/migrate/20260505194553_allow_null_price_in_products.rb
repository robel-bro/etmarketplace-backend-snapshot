class AllowNullPriceInProducts < ActiveRecord::Migration[8.1]
  def change
    change_column_null :products, :price, true
  end
end
