class AddVariantAttributesToPackageProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :package_products, :variant_attributes, :jsonb
  end
end
