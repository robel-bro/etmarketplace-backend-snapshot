class ChangeCategoryIdNullOnProductAttributes < ActiveRecord::Migration[8.1]
  def change
    change_column_null :product_attributes, :category_id, true
  end
end
