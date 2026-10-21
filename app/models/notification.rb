# app/models/notification.rb

class Notification < ApplicationRecord
  belongs_to :user

  enum :notification_type, {
    order_placed: 0,
    new_order: 1,
    order_acceptance_reminder: 2,
    order_accepted: 3,
    order_rejected_by_seller: 4,
    order_auto_cancelled: 5,
    order_auto_cancelled_seller: 6,
    shipment_created: 7,
    shipment_updated: 8,
    delivery_accepted: 9,
    delivery_accepted_seller: 10,
    return_approved: 11,
    return_approved_seller: 12,
    return_rejected: 13,
    payout_paid: 14,
    price_drop_alert: 15,
    flash_deal_started: 16,
    new_collection: 17,
    announcement: 18,
    promotion: 19,
    general: 20,
    vendor_approved: 21,
    vendor_rejected: 22,
    order_accepted_seller: 23
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :unread, -> { where(read: false) }

  validates :title, :body, :notification_type, presence: true

  def mark_read!
    update(read: true) unless read?
  end

  def push_delivered?
    push_status == 'sent'
  end

  def mark_push_sent!
    update(push_status: 'sent', push_sent_at: Time.current)
  end

  def mark_push_failed!(reason = nil)
    meta = (metadata || {}).merge(push_fail_reason: reason)
    update(push_status: 'failed', metadata: meta)
  end
end