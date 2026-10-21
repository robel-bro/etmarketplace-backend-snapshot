class AddHealthFieldsToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :last_login_at, :datetime
    add_column :vendors, :suspension_reason, :text
    add_column :vendors, :declined_orders_count, :integer
    add_column :vendors, :total_orders_count, :integer
    add_column :vendors, :avg_response_time_hours, :float
    add_column :vendors, :unanswered_orders_count, :integer
  end
end
