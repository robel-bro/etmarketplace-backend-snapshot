class AddIsBulkSupplierToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :is_bulk_supplier, :boolean, default: false, null: false
    add_index :vendors, :is_bulk_supplier
  end
end