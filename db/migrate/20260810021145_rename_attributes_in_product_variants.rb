class RenameAttributesInProductVariants < ActiveRecord::Migration[8.1]
  def change
    rename_column :product_variants, :attributes, :variant_attributes
  end
end