class AddNationalIdToVendors < ActiveRecord::Migration[7.0]
  def change
    add_column :vendors, :national_id, :string
    add_index :vendors, :national_id, unique: true
  end
end
