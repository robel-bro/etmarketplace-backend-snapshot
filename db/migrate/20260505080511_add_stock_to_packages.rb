class AddStockToPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :packages, :stock, :integer
  end
end
