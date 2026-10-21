class RestructureUsersForPhoneAuth < ActiveRecord::Migration[8.1]
  def change
    # 1. Rename email_address → email_address_old (if not already done)
    if column_exists?(:users, :email_address)
      rename_column :users, :email_address, :email_address_old
    end

    # 2. Phone – already exists, so we just add a unique index if missing
    add_index :users, :phone, unique: true unless index_exists?(:users, :phone)

    # 3. Phone verification flag
    add_column :users, :phone_verified, :boolean, default: false unless column_exists?(:users, :phone_verified)

    # 4. OTP
    add_column :users, :otp_code, :string unless column_exists?(:users, :otp_code)
    add_column :users, :otp_expires_at, :datetime unless column_exists?(:users, :otp_expires_at)

    # 5. Security
    add_column :users, :failed_attempts, :integer, default: 0 unless column_exists?(:users, :failed_attempts)
    add_column :users, :locked_until, :datetime unless column_exists?(:users, :locked_until)

    # 6. Seller fields
    add_column :users, :national_id, :string unless column_exists?(:users, :national_id)
    add_column :users, :fayda_id, :string unless column_exists?(:users, :fayda_id)
    add_column :users, :shop_name, :string unless column_exists?(:users, :shop_name)
    add_column :users, :shop_location, :string unless column_exists?(:users, :shop_location)
    add_column :users, :tin, :string unless column_exists?(:users, :tin)

    # 7. Full name
    add_column :users, :full_name, :string unless column_exists?(:users, :full_name)

    # 8. FCM token
    add_column :users, :fcm_token, :string unless column_exists?(:users, :fcm_token)
  end
end
