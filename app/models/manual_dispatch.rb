class ManualDispatch < ApplicationRecord
  belongs_to :delivery_request
  belongs_to :logistics_partner, optional: true
  belongs_to :admin_user, class_name: 'User', optional: true

  enum :status, {
    pending: 0,
    contacted: 1,
    accepted: 2,
    picked_up: 3,
    in_transit: 4,
    delivered: 5,
    failed: 6
  }

  validates :delivery_request_id, uniqueness: true
  validate :partner_must_be_manual, if: -> { logistics_partner.present? }

  scope :pending_or_active, -> { where(status: [:pending, :contacted, :accepted, :picked_up, :in_transit]) }

  private

  def partner_must_be_manual
    return unless logistics_partner
    unless logistics_partner.manual?
      errors.add(:logistics_partner, "must be in manual dispatch mode")
    end
  end
end