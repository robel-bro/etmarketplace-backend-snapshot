# app/models/package_product.rb

class PackageProduct < ApplicationRecord
  belongs_to :package, touch: true
  belongs_to :product

  attribute :variant_attributes, :jsonb, default: {}

  before_validation :normalize_variant_attributes

  validate :variant_attributes_is_hash
  validate :variant_attributes_match_product_variants, if: -> { variant_attributes.present? && product.present? }
  validate :variant_attributes_required_for_variant_product, if: -> { product.present? }
  validate :unique_variant_per_package, on: :create

  # ── Available stock for this specific package‑product line ──
  # This method returns the **physical, reservation-aware** stock available
  # to allocate to this package. It deliberately does NOT apply the product's
  # daily sales limit because that limit is meant for individual product
  # ordering, not for bundle packaging.
  def available_stock
    return 0 unless product

    # No variant selected OR product is not variant-based:
    # Use the product's simple stock minus reserved quantity.
    if variant_attributes.blank? || !product.variant_product?
      if product.bulk_enabled? && product.stock.nil?
        # Unlimited bulk product
        Float::INFINITY
      else
        # Simple product: physical stock minus active reservations
        [product.stock.to_i - product.stock_reserved.to_i, 0].max
      end
    else
      # Variant-based product: find the specific variant record
      pv = find_product_variant
      return 0 unless pv

      return Float::INFINITY if pv.unlimited_stock?

      # Variant stock minus its reservation counter (maintained by Product#reserve_stock!)
      [pv.stock.to_i - pv.reserved.to_i, 0].max
    end
  end

  # ── Find the actual ProductVariant record matching variant_attributes ──
  def find_product_variant
    return nil unless product.present? && variant_attributes.present?

    # Use the already-loaded association if possible to avoid N+1.
    if product.product_variants.loaded?
      product.product_variants.find { |pv| pv.variant_attributes == variant_attributes }
    else
      product.product_variants.find_by(variant_attributes: variant_attributes)
    end
  end

  # ── Convenience methods ──
  def variant_price
    return product.price unless product.variant_product? && variant_attributes.present?
    pv = find_product_variant
    pv ? pv.price : product.price
  end

  def variant_available_stock
    available_stock
  end

  private

  def normalize_variant_attributes
    self.variant_attributes = (variant_attributes || {}).transform_keys(&:to_s)
    self.variant_attributes = variant_attributes.each_with_object({}) do |(k, v), h|
      h[k] = v.to_s
    end
  end

  def variant_attributes_is_hash
    errors.add(:variant_attributes, "must be a hash") unless variant_attributes.is_a?(Hash)
  end

  def variant_attributes_match_product_variants
    return unless product.present? && variant_attributes.present?

    # If the product has variants in the DB, check against those
    if product.variant_product? && product.product_variants.any?
      match = product.product_variants.exists?(variant_attributes: variant_attributes)
      unless match
        errors.add(:variant_attributes, "do not match any existing product variant")
      end
    else
      # Fallback: check against variants_data JSON (legacy products)
      return if product.variants_data.blank?

      match = product.variants_data.any? do |v|
        v['attributes'].present? &&
        variant_attributes.all? { |key, val| v['attributes'][key].to_s == val.to_s }
      end
      unless match
        errors.add(:variant_attributes, "do not match any existing product variant")
      end
    end
  end

  def variant_attributes_required_for_variant_product
    # If product has real variants (non-empty attributes), variant_attributes must be present
    return unless product.present? && product.has_real_variants?
    if variant_attributes.blank?
      errors.add(:variant_attributes, "must be selected for a product with variants")
    end
  end

  def unique_variant_per_package
    return unless package.present? && product.present?

    duplicates = package.package_products.any? do |pp|
      # Skip self when checking among unsaved siblings
      pp != self &&
        pp.product_id == product_id &&
        pp.variant_attributes == variant_attributes
    end

    if duplicates
      errors.add(:base, "This product variant is already included in the package")
    end
  end
end