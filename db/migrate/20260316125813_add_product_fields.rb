class AddProductFields < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :min_order, :string, default: "1 piece"
    add_column :products, :original_price, :decimal, precision: 10, scale: 2
  end
end
