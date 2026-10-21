class CreateProductAttributes < ActiveRecord::Migration[8.1]
  def change
    create_table :product_attributes do |t|
      t.string :name
      t.references :category, null: false, foreign_key: true

      t.timestamps
    end
  end
end
