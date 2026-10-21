class CreateBulkOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :bulk_order_items do |t|
      t.references :bulk_order, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity

      t.timestamps
    end
  end
end
