class AddAllowedAttributesToCategories < ActiveRecord::Migration[8.0]
  def change
    add_column :categories, :allowed_attributes, :json, default: []
  end
end
