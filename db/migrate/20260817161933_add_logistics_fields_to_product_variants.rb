# db/migrate/xxxxx_add_logistics_fields_to_product_variants.rb
class AddLogisticsFieldsToProductVariants < ActiveRecord::Migration[8.1]
  def change
    add_column :product_variants, :weight_kg, :decimal, precision: 10, scale: 2
    add_column :product_variants, :length_cm, :decimal, precision: 10, scale: 2
    add_column :product_variants, :width_cm, :decimal, precision: 10, scale: 2
    add_column :product_variants, :height_cm, :decimal, precision: 10, scale: 2
    add_column :product_variants, :refrigerated, :boolean, default: false
    add_column :product_variants, :fragile, :boolean, default: false
  end
end