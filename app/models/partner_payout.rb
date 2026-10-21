class PartnerPayout < ApplicationRecord
  belongs_to :logistics_partner
  belongs_to :delivery_request, optional: true   # ← add this

  enum :status, [:pending, :paid, :cancelled]

  validates :amount, numericality: { greater_than: 0 }
  validates :period_start, :period_end, presence: true
end