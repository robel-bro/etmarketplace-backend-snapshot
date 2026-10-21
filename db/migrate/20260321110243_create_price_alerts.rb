class CreatePriceAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :price_alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.decimal :target_price
      t.boolean :alert_sent, default: false

      t.timestamps
    end
    add_index :price_alerts, [:user_id, :product_id], unique: true
  end
end
