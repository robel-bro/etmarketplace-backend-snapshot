# app/models/reservation.rb

class Reservation < ApplicationRecord
  belongs_to :product
  belongs_to :product_variant, optional: true
  belongs_to :user
  belongs_to :order, optional: true

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :expires_at, presence: true
  validate :expires_at_must_be_future, on: :create
  validate :variant_required_if_product_has_variants, on: :create
  validate :variant_matches_product, on: :create

  scope :active,  -> { where('expires_at > ?', Time.current).where(order_id: nil) }
  scope :expired, -> { where('expires_at <= ?', Time.current).where(order_id: nil) }

  # ── Auto‑sync stock_reserved (product or variant) ──
  after_create  :increment_reserved_stock!
  after_destroy :decrement_reserved_stock!, if: -> { order_id.nil? }

  # ── Class Methods ───────────────────────────────────────

  # Release all expired reservations and recalculate stock.
  # Run this every 1‑2 minutes from background job.
  def self.release_expired!
    expired_ids = expired.pluck(:id)
    return 0 if expired_ids.empty?

    affected_product_ids = expired.where(id: expired_ids).distinct.pluck(:product_id)

    ActiveRecord::Base.transaction do
      # Delete expired reservations
      expired.where(id: expired_ids).delete_all

      # Recalculate stock_reserved for affected products (and their variants)
      affected_product_ids.each do |product_id|
        recalculate_stock_reserved!(product_id)
      end
    end

    Rails.logger.info "Released #{expired_ids.size} expired reservations for #{affected_product_ids.size} products"
    expired_ids.size
  end

  # Recalculate the stock_reserved column for a given product (and variant rows)
  # based on the sum of all active reservations.
  def self.recalculate_stock_reserved!(product_id)
    product = Product.find_by(id: product_id)
    return unless product

    if product.has_real_variants?
      # Recalculate per variant
      variant_reservations = active
                               .where(product_id: product_id)
                               .where.not(product_variant_id: nil)
                               .group(:product_variant_id)
                               .sum(:quantity)

      product.product_variants.each do |variant|
        reserved = variant_reservations.fetch(variant.id, 0)
        variant.update_columns(reserved: reserved)
      end

      # Product-level reserved is sum of all variant reserved
      total_reserved = product.product_variants.sum(:reserved)
      product.update_columns(stock_reserved: total_reserved)
    else
      # Simple product
      total_reserved = active.where(product_id: product_id, product_variant_id: nil).sum(:quantity)
      product.update_columns(stock_reserved: total_reserved)
    end
  end

  private

  # ── Validations ───────────────────────────────────────

  def expires_at_must_be_future
    return unless expires_at.present? && expires_at <= Time.current
    errors.add(:expires_at, "must be in the future")
  end

  def variant_required_if_product_has_variants
    return unless product.present? && product.has_real_variants?
    if product_variant_id.blank?
      errors.add(:product_variant, "must be selected for product with variants")
    end
  end

  def variant_matches_product
    return unless product.present? && product_variant_id.present?
    unless product.product_variants.exists?(id: product_variant_id)
      errors.add(:product_variant, "does not belong to this product")
    end
  end

  # ── Stock sync callbacks ──────────────────────────────

  def increment_reserved_stock!
    if product_variant_id.present?
      ProductVariant.where(id: product_variant_id)
                    .update_all(["reserved = reserved + ?", quantity])
      # Also update product-level reserved sum (simplified – recalc)
      self.class.recalculate_stock_reserved!(product_id)
    else
      Product.where(id: product_id)
             .update_all(["stock_reserved = stock_reserved + ?", quantity])
    end
  end

  def decrement_reserved_stock!
    if product_variant_id.present?
      ProductVariant.where(id: product_variant_id)
                    .update_all(["reserved = GREATEST(reserved - ?, 0)", quantity])
      self.class.recalculate_stock_reserved!(product_id)
    else
      Product.where(id: product_id)
             .update_all(["stock_reserved = GREATEST(stock_reserved - ?, 0)", quantity])
    end
  end
end