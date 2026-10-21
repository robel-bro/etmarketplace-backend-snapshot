class AddAcceptingOrdersToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :accepting_orders, :boolean
    add_column :vendors, :reopen_at, :datetime
  end
end
