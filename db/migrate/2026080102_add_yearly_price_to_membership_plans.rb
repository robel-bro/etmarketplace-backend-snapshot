class AddYearlyPriceToMembershipPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :membership_plans, :yearly_price, :decimal, precision: 10, scale: 2
  end
end