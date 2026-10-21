class AddDeliveryNotesToAddresses < ActiveRecord::Migration[8.1]
  def change
    add_column :addresses, :delivery_notes, :text
  end
end
