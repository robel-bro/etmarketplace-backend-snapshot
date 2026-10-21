class AddMembershipFieldsToPaymentLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_logs, :vendor_id, :bigint
    add_column :payment_logs, :membership_plan_id, :bigint
    add_index :payment_logs, :vendor_id
    add_index :payment_logs, :membership_plan_id
  end
end