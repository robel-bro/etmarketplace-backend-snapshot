class AddProductAttributesToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :product_attributes, :jsonb, default: {}
    add_index :products, :product_attributes, using: :gin
  end
end
