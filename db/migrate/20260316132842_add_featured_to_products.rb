class AddFeaturedToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :featured, :boolean, default: false
    add_column :products, :featured_until, :datetime
    add_column :products, :featured_fee, :decimal, precision: 10, scale: 2
  end
end
