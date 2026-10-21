class AddBusinessAddressToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :business_address, :text
  end
end
