class AddViewsToProducts < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:products, :views)
      add_column :products, :views, :integer, default: 0
    end
  end
end
