class AddDetailsToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :description, :text
    add_column :vendors, :long_description, :text
  end
end
