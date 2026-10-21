class CreatePayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :payouts do |t|
      t.references :vendor, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, default: 0
      t.integer :status, default: 0  # 0 = pending, 1 = paid, 2 = cancelled
      t.date :period_start
      t.date :period_end

      t.timestamps
    end
  end
end
