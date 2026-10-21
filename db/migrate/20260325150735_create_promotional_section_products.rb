class CreatePromotionalSectionProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :promotional_section_products do |t|
      t.references :promotional_section, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.timestamps
    end
    add_index :promotional_section_products, [:promotional_section_id, :product_id], unique: true
  end
end
