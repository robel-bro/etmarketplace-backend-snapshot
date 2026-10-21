class AddIsOpenToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :is_open, :boolean, default: true, null: false
  end
end