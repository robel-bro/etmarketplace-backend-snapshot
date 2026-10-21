class AddMembershipToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :membership_plan_id, :integer
    add_column :vendors, :premium_since, :datetime
    add_foreign_key :vendors, :membership_plans
    add_index :vendors, :membership_plan_id
  end
end
