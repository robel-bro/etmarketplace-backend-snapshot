class AddShippingToPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :packages, :shipping_cost, :decimal
    add_column :packages, :free_shipping, :boolean
  end
end
