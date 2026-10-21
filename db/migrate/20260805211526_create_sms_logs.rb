class CreateSmsLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :sms_logs do |t|
      t.string :phone
      t.text :message
      t.string :status
      t.text :response
      t.integer :attempt

      t.timestamps
    end
  end
end
