class CreateBulkOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :bulk_orders do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :status

      t.timestamps
    end
  end
end
