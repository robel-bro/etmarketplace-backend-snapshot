class AddBankNameToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :bank_name, :string
  end
end
