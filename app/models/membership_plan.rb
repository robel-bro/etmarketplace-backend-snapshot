# app/models/membership_plan.rb

class MembershipPlan < ApplicationRecord
  # JSONB features default
  attribute :features, :jsonb, default: []

  has_many :vendors

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :duration_days, numericality: { only_integer: true, greater_than: 0 }
  validates :commission_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :sponsored_product_limit, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :featured_duration_days, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :active, -> { where(active: true) }

  # ── Tax helpers (Ethiopia, dynamic VAT from Settings) ──
  def vat_rate
    setting = Setting.get('tax_and_fees')
    rate = setting.is_a?(Hash) ? setting['vat_rate'].to_f : 15.0
    rate.positive? ? rate : 15.0   # fallback to 15% if not set
  end

  def price_excluding_vat
    (price / (1 + vat_rate / 100.0)).round(2)
  end

  def vat_amount
    price - price_excluding_vat
  end

  def price_for_display
    price
  end

  # ── Combined features list for seller display ──────────
  def features_list
    list = features.is_a?(Array) ? features.map(&:to_s) : []
    list << "Commission rate: #{commission_rate}%" if commission_rate.present?
    list << "Featured store for #{featured_duration_days} days" if featured_included && featured_duration_days
    list << "Sponsored product slots: #{sponsored_product_limit}" if sponsored_product_limit.to_i > 0
    list << "Priority Support" if priority_support
    list << "Advanced Analytics" if analytics_access
    list
  end
end