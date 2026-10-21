class AddMembershipFieldsToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :membership_expires_at, :datetime
    add_column :vendors, :membership_paid, :boolean, default: false
  end
end
