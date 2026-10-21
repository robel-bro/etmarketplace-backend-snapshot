class CreateOtpLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :otp_logs do |t|
      t.string :phone, null: false
      t.timestamps
    end
    add_index :otp_logs, [:phone, :created_at]
  end
end
