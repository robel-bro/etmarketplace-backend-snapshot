class AllowNullOrderInPaymentLogs < ActiveRecord::Migration[8.1]
  def change
    change_column_null :payment_logs, :order_id, true
  end
end