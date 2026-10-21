class CreateCategoryAttributes < ActiveRecord::Migration[8.1]
  def change
    create_table :category_attributes do |t|
      t.integer :category_id
      t.integer :attribute_id
      t.boolean :is_required

      t.timestamps
    end
  end
end
