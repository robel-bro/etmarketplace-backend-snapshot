class CreatePartnerPayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :partner_payouts do |t|
      t.references :logistics_partner, null: false, foreign_key: true
      t.references :delivery_request, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2
      t.integer :status
      t.date :period_start
      t.date :period_end
      t.datetime :paid_at

      t.timestamps
    end
  end
end
