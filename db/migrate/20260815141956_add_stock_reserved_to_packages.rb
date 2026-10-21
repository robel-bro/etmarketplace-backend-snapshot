class AddStockReservedToPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :packages, :stock_reserved, :integer, default: 0, null: false
    add_index :packages, :stock_reserved
  end
end