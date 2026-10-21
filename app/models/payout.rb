class Payout < ApplicationRecord
  belongs_to :vendor
  has_many :order_payouts, dependent: :destroy
  has_many :orders, through: :order_payouts

  # ─── Status enum (preserves old integer values for existing records) ───
  enum :status, {
    pending:    0,   # unchanged
    paid:       1,   # unchanged
    cancelled:  2,   # unchanged
    processing: 3,   # ★ new
    failed:     4,   # ★ new
    rejected:   5    # ★ new
  }

  # … any other code you already have (validations, scopes, etc.) stays below …
end