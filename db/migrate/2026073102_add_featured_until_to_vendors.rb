class AddFeaturedUntilToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :featured_until, :datetime
    add_column :vendors, :sponsored_products_count, :integer, default: 0
  end
end