# app/models/product_variant.rb
class ProductVariant < ApplicationRecord
  belongs_to :product, touch: true

  validates :price, numericality: { greater_than: 0 }
  validates :stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :reserved, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_save :ensure_reserved_not_exceeding_stock

  # ── Atomic stock deduction ──
  def self.decrement_stock!(variant_id, quantity)
    affected = ProductVariant
      .where(id: variant_id)
      .where('stock - reserved >= ?', quantity)
      .update_all("stock = stock - #{quantity.to_i}, reserved = reserved + #{quantity.to_i}")
    affected > 0
  end

  # ── Release reserved stock ──
  def self.release_reserved!(variant_id, quantity)
    ProductVariant
      .where(id: variant_id)
      .update_all("reserved = GREATEST(reserved - #{quantity.to_i}, 0)")
  end

  # ★ FIXED: unlimited_stock flag overrides stored stock
  def available_stock
    return Float::INFINITY if unlimited_stock?
    [stock - reserved, 0].max
  end

  def out_of_stock?
    return false if unlimited_stock?
    available_stock <= 0
  end

  def variant_attributes_hash
    self[:variant_attributes] || {}
  end

  private

  def ensure_reserved_not_exceeding_stock
    return if stock.nil?
    self.reserved = stock if reserved > stock
  end
end