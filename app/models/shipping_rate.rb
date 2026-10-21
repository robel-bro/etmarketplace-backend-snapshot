# app/models/shipping_rate.rb
class ShippingRate < ApplicationRecord
  belongs_to :region
  belongs_to :zone, optional: true
  belongs_to :woreda, optional: true

  validates :standard_rate, :express_rate, numericality: { greater_than_or_equal_to: 0 }
  validates :standard_days, :express_days, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :specificity_consistency

  def self.for_address(address)
    where(region: address.region)
      .where(zone: address.zone)
      .where(woreda: address.woreda)
      .or(where(region: address.region, zone: address.zone, woreda: nil))
      .or(where(region: address.region, zone: nil, woreda: nil))
      .order(Arel.sql("CASE WHEN woreda_id IS NOT NULL THEN 0 WHEN zone_id IS NOT NULL THEN 1 ELSE 2 END"))
      .first
  end

  private

  def specificity_consistency
    if woreda.present? && zone.nil?
      errors.add(:zone, "must be present when woreda is specified")
    end
    if zone.present? && region != zone.region
      errors.add(:zone, "must belong to the selected region")
    end
    if woreda.present? && woreda.zone != zone
      errors.add(:woreda, "must belong to the selected zone")
    end
  end
end