class AddNotificationPrefsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_notifications, :boolean, default: true, null: false
    add_column :users, :sms_notifications, :boolean, default: true, null: false
    add_column :users, :push_notifications, :boolean, default: true, null: false
    add_column :users, :promotional_emails, :boolean, default: false, null: false
  end
end
