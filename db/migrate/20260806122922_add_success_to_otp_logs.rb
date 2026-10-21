class AddSuccessToOtpLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :otp_logs, :success, :boolean
  end
end
