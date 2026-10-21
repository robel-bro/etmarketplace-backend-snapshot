class CreateVendors < ActiveRecord::Migration[8.1]
  def change
    create_table :vendors do |t|
      t.references :user, null: false, foreign_key: true
      t.string :business_name
      t.string :business_license
      t.string :tin
      t.string :id_document
      t.integer :status, default: 0  # 0 = pending
      t.datetime :approved_at
      t.datetime :rejected_at
      t.text :rejection_reason
      t.decimal :commission_rate, precision: 5, scale: 2
      t.boolean :premium, default: false
      t.datetime :premium_expires_at

      t.timestamps
    end
  end
end
