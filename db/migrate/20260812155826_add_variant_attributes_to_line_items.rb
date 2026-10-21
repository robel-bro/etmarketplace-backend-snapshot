class AddVariantAttributesToLineItems < ActiveRecord::Migration[8.1]
  def change
    add_column :line_items, :variant_attributes, :jsonb, default: {}
    add_index :line_items, :variant_attributes, using: :gin
  end
end