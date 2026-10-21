class AddSupplierFieldsToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :verified, :boolean, default: false
    add_column :vendors, :pro, :boolean, default: false
    add_column :vendors, :years_in_business, :integer, default: 1
    add_column :vendors, :country, :string, default: "ET"
    add_column :vendors, :rating, :decimal, precision: 2, scale: 1, default: 0.0
    add_column :vendors, :reviews_count, :integer, default: 0
    add_column :vendors, :reorder_rate, :integer, default: 0
  end
end
