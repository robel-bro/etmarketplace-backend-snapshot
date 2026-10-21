class AddSellerPaysShipping < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :seller_pays_shipping, :boolean, default: false
    add_column :products, :shipping_subsidy_type, :string       # 'full', 'percentage', 'fixed'
    add_column :products, :shipping_subsidy_value, :decimal, precision: 10, scale: 2

    # Packages already have shipping_type & shipping_value, but we add subsidy fields too
    add_column :packages, :seller_pays_shipping, :boolean, default: false
    add_column :packages, :shipping_subsidy_type, :string
    add_column :packages, :shipping_subsidy_value, :decimal, precision: 10, scale: 2
  end
end
