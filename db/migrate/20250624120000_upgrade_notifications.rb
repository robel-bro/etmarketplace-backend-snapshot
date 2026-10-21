class UpgradeNotifications < ActiveRecord::Migration[8.1]
  def up
    # 1. Convert notification_type to integer enum
    add_column :notifications, :notification_type_int, :integer

    mapping = {
      'order_placed' => 0, 'new_order' => 1, 'order_acceptance_reminder' => 2,
      'order_accepted' => 3, 'order_rejected_by_seller' => 4,
      'order_auto_cancelled' => 5, 'order_auto_cancelled_seller' => 6,
      'shipment_created' => 7, 'shipment_updated' => 8, 'delivery_accepted' => 9,
      'delivery_accepted_seller' => 10, 'return_approved' => 11,
      'return_approved_seller' => 12, 'return_rejected' => 13, 'payout_paid' => 14,
      'price_drop_alert' => 15, 'flash_deal_started' => 16, 'new_collection' => 17,
      'announcement' => 18, 'promotion' => 19, 'general' => 20
    }
    Notification.reset_column_information
    Notification.find_each do |n|
      int_val = mapping[n.notification_type] || 20
      n.update_column(:notification_type_int, int_val)
    end

    remove_column :notifications, :notification_type
    rename_column :notifications, :notification_type_int, :notification_type

    # 2. Delivery tracking columns
    add_column :notifications, :push_status, :string, default: 'pending'
    add_column :notifications, :push_sent_at, :datetime
    add_column :notifications, :email_status, :string, default: 'pending'
    add_column :notifications, :sms_status, :string, default: 'pending'

    # 3. Performance indexes
    add_index :notifications, [:user_id, :created_at]
    add_index :notifications, [:user_id, :read]
    add_index :notifications, :notification_type

    # 4. Ensure metadata is jsonb
    change_column :notifications, :metadata, :jsonb, using: 'metadata::jsonb' rescue nil
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
