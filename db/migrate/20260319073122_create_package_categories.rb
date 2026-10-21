class CreatePackageCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :package_categories do |t|
      t.references :package, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.timestamps
    end
    add_index :package_categories, [:package_id, :category_id], unique: true
  end
end
