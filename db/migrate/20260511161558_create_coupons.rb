class CreateCoupons < ActiveRecord::Migration[8.1]
  def change
    create_table :coupons do |t|
      t.string :code
      t.string :discount_type
      t.float :discount_value
      t.float :min_order_amount
      t.date :start_date
      t.date :end_date
      t.integer :usage_limit
      t.integer :per_user
      t.integer :used_count
      t.boolean :active

      t.timestamps
    end
  end
end
