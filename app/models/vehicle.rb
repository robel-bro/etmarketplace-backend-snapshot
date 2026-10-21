# app/models/vehicle.rb
class Vehicle < ApplicationRecord
  belongs_to :logistics_partner
  has_many :drivers
  has_many :delivery_requests, foreign_key: :vehicle_id

  # ── Statuses ─────────────────────────────────────────
  STATUSES = %w[available busy maintenance].freeze

  # ── Validations ──────────────────────────────────────
  validates :vehicle_type, :plate_number, :max_weight_kg, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :max_weight_kg, numericality: { greater_than: 0 }
  validates :length_cm, :width_cm, :height_cm, numericality: { greater_than: 0 }, allow_nil: true
  validates :max_volume_cm3, numericality: { greater_than: 0 }, allow_nil: true

  # ── Scopes ───────────────────────────────────────────
  scope :available, -> { where(status: 'available') }
  scope :busy, -> { where(status: 'busy') }
  scope :maintenance, -> { where(status: 'maintenance') }
  scope :matching_type, ->(type) { where(vehicle_type: type) if type.present? }

  # Scope: vehicles that can carry at least the given weight
  scope :with_capacity, ->(weight_kg) {
    where("max_weight_kg >= ?", weight_kg) if weight_kg.present?
  }

  # Scope: vehicles that can handle the given volume if max_volume_cm3 is set
  scope :with_volume_capacity, ->(volume_cm3) {
    where("max_volume_cm3 IS NULL OR max_volume_cm3 >= ?", volume_cm3) if volume_cm3.present?
  }

  # Scope: vehicles that support required features (refrigerated, fragile)
  scope :with_features, ->(refrigerated: false, fragile: false) {
    scope = all
    scope = scope.where(refrigerated: true) if refrigerated
    scope = scope.where(fragile_capable: true) if fragile
    scope
  }

  # ── Instance Methods ─────────────────────────────────
  def available?
    status == 'available'
  end

  def busy?
    status == 'busy'
  end

  def maintenance?
    status == 'maintenance'
  end

  def mark_available!
    update!(status: 'available')
  end

  def mark_busy!
    update!(status: 'busy')
  end

  def mark_maintenance!
    update!(status: 'maintenance')
  end

  # Effective maximum volume for this vehicle.
  # Prefer explicit max_volume_cm3 if set; otherwise compute from dimensions.
  def maximum_volume_cm3
    return max_volume_cm3 if max_volume_cm3.present?
    return nil unless length_cm && width_cm && height_cm
    length_cm * width_cm * height_cm
  end

  # Check if vehicle can handle the given load.
  def can_handle?(total_weight, total_volume = nil, requires_refrigerated: false, fragile: false)
    return false unless available?
    return false if max_weight_kg.nil? || max_weight_kg < total_weight.to_f
    return false if requires_refrigerated && !refrigerated?
    return false if fragile && !fragile_capable?

    if total_volume.present?
      vol_limit = maximum_volume_cm3
      return false if vol_limit.present? && total_volume.to_f > vol_limit
    end

    true
  end

  # Alias for backward compatibility
  alias can_carry? can_handle?
end