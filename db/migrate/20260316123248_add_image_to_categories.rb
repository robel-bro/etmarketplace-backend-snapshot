class AddImageToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :image, :string
  end
end
