class CreateUserConsents < ActiveRecord::Migration[8.1]
  def change
    create_table :user_consents do |t|
      t.references :user, null: false, foreign_key: true
      t.string :agreement_type, null: false   # 'terms', 'privacy', etc.
      t.integer :agreement_version, null: false
      t.datetime :accepted_at, null: false
      t.string :ip_address
      t.timestamps
    end
    add_index :user_consents, [:user_id, :agreement_type], unique: true
  end
end