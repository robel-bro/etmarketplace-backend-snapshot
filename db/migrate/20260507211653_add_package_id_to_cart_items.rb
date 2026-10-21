class AddPackageIdToCartItems < ActiveRecord::Migration[8.1]
  def change
    add_column :cart_items, :package_id, :integer
  end
end
