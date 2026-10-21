class AddPhoneToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :phone, :string
  end
end
