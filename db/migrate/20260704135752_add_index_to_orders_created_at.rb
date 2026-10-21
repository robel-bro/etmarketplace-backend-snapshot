class AddIndexToOrdersCreatedAt < ActiveRecord::Migration[8.1]
  def change
    add_index :orders, :created_at
  end
end