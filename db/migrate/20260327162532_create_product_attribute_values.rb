class CreateProductAttributeValues < ActiveRecord::Migration[8.1]
  def change
    create_table :product_attribute_values do |t|
      t.references :product, null: false, foreign_key: true
      t.references :product_attribute, null: false, foreign_key: true
      t.string :value

      t.timestamps
    end
  end
end
