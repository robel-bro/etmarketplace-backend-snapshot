class AddFeaturedToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :featured, :boolean
  end
end
