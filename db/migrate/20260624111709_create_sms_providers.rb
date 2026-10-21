class CreateSmsProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :sms_providers do |t|
      t.string :name, null: false
      t.string :provider, null: false
      t.string :api_key
      t.string :phone_number
      t.string :auth_token
      t.string :username
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :sms_providers, :provider, unique: true
  end
end
