# app/models/address.rb
class Address < ApplicationRecord
  belongs_to :user
  belongs_to :region
  belongs_to :zone, optional: true
  belongs_to :woreda, optional: true

  # ─── New columns (added via migration) ──────────────
  # city (string)          – e.g., "Addis Ababa"
  # woreda_text (string)   – text representation of woreda (e.g., "Woreda 03")
  # street (string)        – street name
  # source (string)        – "auto" or "manual"
  # Existing: sub_city, landmark, latitude, longitude, building_name, delivery_notes

  validates :phone, presence: true
  validate :woreda_belongs_to_zone, if: -> { woreda.present? }
  validate :zone_belongs_to_region, if: -> { zone.present? }
  validate :require_coordinates_or_address_line

  after_save :ensure_single_default, if: :is_default?
  before_validation :set_phone_from_user, on: :create, if: -> { phone.blank? }
  before_save :geocode_if_needed

  # ─── Full address display ──────────────────────────
  def full_address
    parts = []
    parts << building_name if building_name.present?
    parts << street if respond_to?(:street) && street.present?
    parts << sub_city if sub_city.present?
    parts << woreda_text if respond_to?(:woreda_text) && woreda_text.present?
    parts << woreda.name if woreda
    parts << zone.name if zone
    parts << city if respond_to?(:city) && city.present?
    parts << region.name if region
    parts << address_line if address_line.present?
    parts << landmark if landmark.present?
    parts.compact.join(", ")
  end

  private

  def set_phone_from_user
    self.phone = user.phone if user&.phone.present?
  end

  def require_coordinates_or_address_line
    if latitude.blank? && longitude.blank? && address_line.blank?
      errors.add(:base, "Provide either coordinates (latitude/longitude) or an address line")
    end
  end

  def geocode_if_needed
    # Skip if we already have coordinates and they haven't changed (avoid re‑geocoding)
    return if latitude.present? && longitude.present? && !address_line_changed?
    # Skip if no address line and no coordinates (manual pin will provide coordinates directly)
    return if address_line.blank?

    # If user manually provided coordinates (source = 'manual'), respect them
    if source == 'manual' && latitude.present? && longitude.present?
      # still fill in text components via reverse geocode if missing
      enrich_components_from_coordinates unless components_complete?
      return
    end

    # Use the Ultimate Detection Engine
    result = GeocodingService.forward_structured(address_line)
    if result && result[:lat] != 9.0243  # not default fallback
      self.latitude = result[:lat]
      self.longitude = result[:lng]
      self.source ||= 'auto'

      # Populate new fields if they exist in schema
      struct = result[:structured] || {}
      self.city = struct[:city] if respond_to?(:city=) && struct[:city].present?
      self.sub_city = struct[:sub_city] if struct[:sub_city].present?
      self.woreda_text = struct[:woreda] if respond_to?(:woreda_text=) && struct[:woreda].present?
      self.street = struct[:street] if respond_to?(:street=) && struct[:street].present?
      self.landmark = struct[:landmark] if struct[:landmark].present? && landmark.blank?
      self.formatted_address = result[:formatted_address] if respond_to?(:formatted_address=)
    else
      # Fallback to basic geocode
      basic = GeocodingService.geocode(address_line)
      self.latitude = basic[:lat]
      self.longitude = basic[:lng]
      self.source ||= 'auto'
    end
  rescue => e
    Rails.logger.warn "Geocoding failed for address #{id}: #{e.message}"
  end

  def enrich_components_from_coordinates
    return unless latitude && longitude
    result = GeocodingService.reverse_geocode_with_structure(latitude, longitude)
    return unless result
    struct = result[:structured] || {}
    self.city = struct[:city] if respond_to?(:city=) && self.city.blank?
    self.sub_city = struct[:sub_city] if self.sub_city.blank?
    self.woreda_text = struct[:woreda] if respond_to?(:woreda_text=) && self.woreda_text.blank?
    self.street = struct[:street] if respond_to?(:street=) && self.street.blank?
    self.landmark = struct[:landmark] if self.landmark.blank?
  end

  def components_complete?
    %i[city sub_city woreda_text street].all? do |field|
      self.respond_to?(field) && self.send(field).present?
    end
  end

  def woreda_belongs_to_zone
    if zone.nil? || woreda.zone != zone
      errors.add(:woreda, "must belong to the selected zone")
    end
  end

  def zone_belongs_to_region
    if zone.region != region
      errors.add(:zone, "must belong to the selected region")
    end
  end

  def ensure_single_default
    user.addresses.where.not(id: id).update_all(is_default: false) if is_default?
  end
end