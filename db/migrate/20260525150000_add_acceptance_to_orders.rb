class AddAcceptanceToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :acceptance_deadline, :datetime
    add_column :orders, :accepted_at, :datetime
    add_column :orders, :rejected_at, :datetime
  end
end
