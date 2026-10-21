class FinancialLedger < ApplicationRecord
  belongs_to :ledgerable, polymorphic: true, optional: true

  validates :transaction_type, presence: true
  validates :amount, numericality: { other_than: 0 }
  validates :description, presence: true

  scope :recent, -> { order(created_at: :desc).limit(100) }
  scope :by_type, ->(type) { where(transaction_type: type) }
  scope :between, ->(start_date, end_date) {
    where(created_at: start_date.beginning_of_day..end_date.end_of_day)
  }

  TYPES = %w[
    customer_payment
    commission_revenue
    service_fee
    membership_revenue
    seller_payout
    delivery_payout
    refund
    tax_remittance
    cod_remittance
    funds_release_seller
    funds_release_commission
    funds_release_service_fee
    funds_release_vat
    payout_created
    payout_completed
    payout_rejected
    tax_withheld
    refund_clawback
  ].freeze

  validates :transaction_type, inclusion: { in: TYPES }
end