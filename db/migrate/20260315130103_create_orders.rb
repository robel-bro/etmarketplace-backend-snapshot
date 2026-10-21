class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :vendor, null: false, foreign_key: true
      t.decimal :total, precision: 10, scale: 2, null: false, default: 0
      t.integer :status, default: 0  # 0 = pending
      t.text :shipping_address, null: false
      t.string :payment_method
      t.integer :payment_status, default: 0  # 0 = pending
      t.decimal :commission_amount, precision: 10, scale: 2, default: 0
      t.decimal :commission_rate, precision: 5, scale: 2  # stored at time of order

      t.timestamps
    end
  end
end
