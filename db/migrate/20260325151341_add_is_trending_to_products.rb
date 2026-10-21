class AddIsTrendingToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :is_trending, :boolean, default: false
    add_index :products, :is_trending
  end
end
