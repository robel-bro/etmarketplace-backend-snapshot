# app/models/line_item.rb

class LineItem < ApplicationRecord
  belongs_to :order
  belongs_to :product, optional: true
  belongs_to :package, optional: true

  attribute :variant_attributes, :jsonb, default: {}

  validates :quantity, numericality: { greater_than: 0 }
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validate :exactly_one_product_or_package
  validate :variant_required_for_variant_product

  before_validation :set_price, on: :create

  private

  def set_price
    # Use current_price (discounted price) for snapshot, fallback to 0
    if price.nil? || price.zero?
      self.price = product&.current_price || package&.current_price || 0
    end
  end

  def exactly_one_product_or_package
    if product_id.present? && package_id.present?
      errors.add(:base, "Line item cannot reference both product and package")
    elsif product_id.blank? && package_id.blank?
      errors.add(:base, "Line item must reference either a product or a package")
    end
  end

  def variant_required_for_variant_product
    return unless product.present?
    if product.has_real_variants? && variant_attributes.blank?
      errors.add(:variant_attributes, "must be selected for product with variants")
    end
  end
end