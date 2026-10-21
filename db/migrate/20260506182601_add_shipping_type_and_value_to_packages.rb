class AddShippingTypeAndValueToPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :packages, :shipping_type, :integer, default: nil   # 0=free, 1=flat, 2=percentage
    add_column :packages, :shipping_value, :decimal, precision: 10, scale: 2

    # Optional – remove old columns (if you already have them and want to clean up)
    # remove_column :packages, :shipping_cost, :decimal
    # remove_column :packages, :free_shipping, :boolean
  end
end
