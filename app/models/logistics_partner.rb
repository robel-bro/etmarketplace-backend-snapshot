# app/models/logistics_partner.rb

class LogisticsPartner < ApplicationRecord
  # Associations
  has_many :vehicles, dependent: :destroy
  has_many :drivers, dependent: :destroy
  has_many :rate_cards, dependent: :destroy
  has_many :delivery_requests, dependent: :nullify
  has_many :manual_dispatches, dependent: :nullify

  has_one :user, dependent: :nullify

  has_one_attached :logo
  has_one_attached :business_license_doc
  has_one_attached :tin_doc
  has_one_attached :insurance_doc

  # Enums
  enum :status, { pending: 0, verified: 1, active: 2, suspended: 3 }
  enum :dispatch_mode, { manual: 0, external_api: 1, internal_fleet: 2 }

  # Validations
  validates :name, :phone, presence: true
  validates :status, inclusion: { in: statuses.keys }
  validates :dispatch_mode, inclusion: { in: dispatch_modes.keys }
  validates :commission_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  # Scopes
  scope :active, -> { where(status: :active) }
  scope :online, -> { where(online: true) }
  scope :internal_fleet, -> { where(dispatch_mode: :internal_fleet) }

  # Class Methods
  def self.available_for_order(vehicle_type, weight_kg, volume_cm3 = nil, refrigerated: false, fragile: false)
    vehicle_conditions = { status: :available }
    vehicle_conditions[:vehicle_type] = vehicle_type if vehicle_type.present?
    vehicle_conditions[:max_weight_kg] = (weight_kg..Float::INFINITY) if weight_kg.present?
    vehicle_conditions[:refrigerated] = true if refrigerated
    vehicle_conditions[:fragile_capable] = true if fragile

    active
      .online
      .internal_fleet
      .joins(:vehicles)
      .where(vehicles: vehicle_conditions)
      .distinct
  end

  # Instance Methods
  def ready_for_orders?
    active? && online?
  end

  def go_online!
    update!(online: true)
  end

  def go_offline!
    update!(online: false)
  end

  def estimate_price(vehicle_type, distance_km, total_weight_kg = 0, express: false, fragile: false)
    return nil unless active?

    card = rate_cards.find_by(vehicle_type: vehicle_type)
    if card
      base = card.base_rate.to_f
      per_km = card.per_km_rate.to_f
      min_charge = card.min_charge.to_f
      weight_surcharge = card.weight_surcharge_per_kg_above_5kg.to_f
      express_surcharge = card.express_surcharge_percent.to_f
      fragile_surcharge = card.fragile_surcharge.to_f
    else
      base = self.base_rate.to_f
      per_km = self.per_km_rate.to_f
      min_charge = self.min_charge.to_f
      weight_surcharge = 0.0
      express_surcharge = 0.0
      fragile_surcharge = 0.0
    end

    cost = base + (distance_km.to_f * per_km)
    if total_weight_kg.to_f > 5
      cost += (total_weight_kg.to_f - 5) * weight_surcharge
    end
    if express
      cost += cost * (express_surcharge / 100.0)
    end
    cost += fragile_surcharge if fragile
    cost = [cost, min_charge].max
    cost.round(2)
  end

  def calculate_quote(distance_km, total_weight_kg = 0)
    estimate_price('car', distance_km, total_weight_kg)
  end

  def can_fulfill?(vehicle_type, weight_kg, volume_cm3 = nil, refrigerated: false, fragile: false)
    query = vehicles.available
    query = query.where(vehicle_type: vehicle_type) if vehicle_type.present?
    query = query.where("max_weight_kg >= ?", weight_kg) if weight_kg.present?
    query = query.where(refrigerated: true) if refrigerated
    query = query.where(fragile_capable: true) if fragile
    query.exists?
  end

  # ⚠️ Raises exceptions instead of swallowing them
  def activate!
    raise "Cannot activate: partner is not verified" unless verified?
    update!(status: :active, online: true)
    Rails.logger.info "Partner #{id} (#{name}) activated."
    true
  end

  def suspend!(reason = nil)
    update!(status: :suspended, online: false)
    Rails.logger.info "Partner #{id} suspended. Reason: #{reason || 'unspecified'}"
    true
  end
end