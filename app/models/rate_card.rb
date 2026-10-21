# app/models/rate_card.rb

class RateCard < ApplicationRecord
  belongs_to :logistics_partner

  # ── Validations ──────────────────────────────────────
  validates :vehicle_type, presence: true
  validates :base_rate, :per_km_rate, :min_charge, numericality: { greater_than_or_equal_to: 0 }
  validates :vehicle_type, uniqueness: { scope: :logistics_partner_id }
  validates :weight_surcharge_per_kg_above_5kg, :express_surcharge_percent, :fragile_surcharge,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # ── Instance Methods ─────────────────────────────────
  # Calculate total price for a delivery job.
  def calculate_price(distance_km, total_weight_kg = 0, express: false, fragile: false)
    distance = distance_km.to_f
    weight = total_weight_kg.to_f

    charge = base_rate.to_f + (per_km_rate.to_f * distance)
    charge = [charge, min_charge.to_f].max

    if weight > 5
      charge += (weight - 5) * weight_surcharge_per_kg_above_5kg.to_f
    end

    charge += (charge * express_surcharge_percent.to_f / 100.0) if express
    charge += fragile_surcharge.to_f if fragile

    charge.round(2)
  end

  # ── Class Methods ────────────────────────────────────
  # Returns an unsaved RateCard built from system-wide defaults.
  # This is used as a fallback when a partner has not set a specific rate card.
  def self.default_for(vehicle_type)
    settings = Setting.get('logistics_defaults') || {}
    defaults = settings['rate_cards'] || {}
    data = defaults[vehicle_type.to_s] || defaults[vehicle_type.to_sym] || {}

    new(
      vehicle_type: vehicle_type.to_s,
      base_rate: data['base_rate'] || data[:base_rate] || 50,
      per_km_rate: data['per_km_rate'] || data[:per_km_rate] || 15,
      min_charge: data['min_charge'] || data[:min_charge] || 100,
      weight_surcharge_per_kg_above_5kg: data['weight_surcharge_per_kg_above_5kg'] || data[:weight_surcharge_per_kg_above_5kg] || 2,
      express_surcharge_percent: data['express_surcharge_percent'] || data[:express_surcharge_percent] || 30,
      fragile_surcharge: data['fragile_surcharge'] || data[:fragile_surcharge] || 50
    )
  end
end