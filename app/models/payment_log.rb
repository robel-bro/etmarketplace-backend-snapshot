class PaymentLog < ApplicationRecord
  belongs_to :order, optional: true
  belongs_to :vendor, optional: true
  belongs_to :membership_plan, optional: true

  validates :idempotency_key, uniqueness: true, allow_nil: true
  validates :status, inclusion: { in: %w[pending completed failed] }

  scope :for_order, ->(order) { where(order: order) }
end