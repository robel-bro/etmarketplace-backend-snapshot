class AddStockReservedToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :stock_reserved, :integer, default: 0, null: false
  end
end