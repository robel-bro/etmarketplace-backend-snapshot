# app/models/admin_audit_log.rb

class AdminAuditLog < ApplicationRecord
  belongs_to :admin_user, class_name: 'User', inverse_of: :admin_audit_logs
  belongs_to :auditable, polymorphic: true, optional: true

  validates :action, presence: true
  validates :admin_user, presence: true

  # Central logging method – safe, never raises.
  def self.log(admin_user, action, record = nil, metadata = {})
    create!(
      admin_user: admin_user,
      action: action,
      auditable: record,
      metadata: metadata || {},
      ip_address: nil   # ← Do NOT reference Current (undefined constant)
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create AdminAuditLog: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "AdminAuditLog unexpected error: #{e.message}"
    nil
  end
end