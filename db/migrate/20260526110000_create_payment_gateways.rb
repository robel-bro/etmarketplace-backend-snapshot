class CreatePaymentGateways < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_gateways do |t|
      t.string :name, null: false             # e.g. "Telebirr", "Chapa"
      t.string :provider, null: false         # e.g. "telebirr", "chapa", "bank_x"
      t.string :api_key
      t.string :merchant_id
      t.string :webhook_secret
      t.boolean :active, default: true
      t.boolean :supports_refunds, default: false
      t.jsonb :config, default: {}            # extra provider‑specific fields
      t.timestamps
    end

    add_index :payment_gateways, :provider, unique: true
  end
end
