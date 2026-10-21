class AddFeaturesToMembershipPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :membership_plans, :features, :jsonb
  end
end
