class CreateReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :reservations do |t|
      t.references :product, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :order, foreign_key: true                   # nullable – linked once order is placed
      t.integer    :quantity, null: false, default: 1
      t.datetime   :expires_at, null: false
      t.timestamps
    end

    add_index :reservations, :expires_at
    add_index :reservations, [:product_id, :user_id], unique: true, where: "order_id IS NULL", name: 'index_active_reservations_on_product_user'
  end
end