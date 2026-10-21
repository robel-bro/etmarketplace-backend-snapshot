class AddLimitsToMembershipPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :membership_plans, :featured_included, :boolean, default: false
    add_column :membership_plans, :featured_duration_days, :integer
    add_column :membership_plans, :sponsored_product_limit, :integer, default: 0
    add_column :membership_plans, :analytics_access, :boolean, default: false
  end
end