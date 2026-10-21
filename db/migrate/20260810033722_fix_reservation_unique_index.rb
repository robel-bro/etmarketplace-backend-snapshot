class FixReservationUniqueIndex < ActiveRecord::Migration[8.1]
  def up
    # Remove the old unique constraint that covers all rows
    remove_index :reservations, name: 'index_active_reservations_on_product_user'
    # Add a partial unique index only for rows that are NOT linked to an order
    add_index :reservations, [:product_id, :user_id],
              unique: true,
              where: "order_id IS NULL",
              name: 'index_active_reservations_on_product_user'
  end

  def down
    remove_index :reservations, name: 'index_active_reservations_on_product_user'
    add_index :reservations, [:product_id, :user_id], unique: true, name: 'index_active_reservations_on_product_user'
  end
end