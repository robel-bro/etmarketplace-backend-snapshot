class CreateOrderPayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :order_payouts do |t|
      t.references :order, null: false, foreign_key: true
      t.references :payout, null: false, foreign_key: true

      t.timestamps
    end
    add_index :order_payouts, [:order_id, :payout_id], unique: true
  end
end
