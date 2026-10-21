class AddFormattedAddressToAddresses < ActiveRecord::Migration[8.1]
  def change
    add_column :addresses, :formatted_address, :string
  end
end
