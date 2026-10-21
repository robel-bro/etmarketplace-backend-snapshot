class AddPhoneAndVerificationToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :phone, :string
    add_column :users, :phone_verified, :boolean, default: false
    add_column :users, :national_id, :string
    add_index :users, :phone, unique: true
  end
end
