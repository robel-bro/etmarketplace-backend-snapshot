class AddVariantAttributesToCartItems < ActiveRecord::Migration[8.1]
  def change
    add_column :cart_items, :variant_attributes, :jsonb, default: {}
  end
end
