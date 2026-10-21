class CreatePaymentLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_logs do |t|
      t.references :order, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2
      t.string :payment_method
      t.string :idempotency_key
      t.string :transaction_id
      t.string :status, default: 'pending'   # pending, completed, failed
      t.text :error_message
      t.timestamps
    end
    add_index :payment_logs, :idempotency_key, unique: true
  end
end
