# app/models/cart_item.rb

class CartItem < ApplicationRecord
  RESERVATION_HOLD_MINUTES = 15  # fixed industry-standard hold

  belongs_to :cart
  belongs_to :product, optional: true
  belongs_to :package, optional: true

  attribute :variant_attributes, :jsonb, default: {}
  attribute :base_price, :decimal, precision: 10, scale: 2, default: 0.0

  # When set to true, after_destroy will NOT release stock.
  # Used by release_and_destroy! (already released manually) and destroy_for_checkout! (stock converted to order).
  attr_accessor :skip_stock_release_on_destroy

  validates :quantity, numericality: { greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :base_price, numericality: { greater_than_or_equal_to: 0 }
  validate :product_or_package_present
  validate :stock_available_on_add, on: :create
  validate :variant_required_if_product_has_variants
  validate :daily_quantity_limit_per_product, on: [:create, :update]
  validate :immutable_product_package_assignment, on: :update
  validate :unique_product_variant_or_package_in_cart, on: :create

  before_validation :set_expiry, on: [:create, :update]
  before_validation :set_pricing

  after_create  :reserve_stock!
  after_update  :handle_stock_change, if: :stock_relevant_change?
  after_destroy :release_stock!, unless: :skip_stock_release_on_destroy

  # ── Associations helper ──
  def vendor
    product&.vendor || package&.vendor
  end

  # ── Stock validation at add time ──
  def stock_available_on_add
    if product_id.present?
      prod = Product.find_by(id: product_id)
      if prod.nil?
        errors.add(:product, "not found")
        return
      end

      unless prod.status == 'active' && prod.vendor&.accepting_orders?
        errors.add(:product, "is not available for ordering")
        return
      end

      chosen_variant = variant_attributes.presence

      if prod.has_real_variants?
        if chosen_variant.blank?
          errors.add(:variant_attributes, "must be selected for product with variants")
          return
        end
        unless prod.can_fulfill?(quantity, variant: chosen_variant)
          errors.add(:quantity, "exceeds available stock for the selected variant")
        end
      else
        unless prod.can_fulfill?(quantity)
          errors.add(:quantity, "exceeds available stock for #{prod.title}")
        end
      end

      # Daily limit check already handled by separate validation, but keep here for safety
    elsif package_id.present?
      pkg = Package.find_by(id: package_id)
      if pkg.nil?
        errors.add(:package, "not found")
        return
      end

      unless pkg.status == 'active' && pkg.vendor&.accepting_orders?
        errors.add(:package, "is not available for ordering")
        return
      end

      if pkg.out_of_stock?
        errors.add(:quantity, "package is out of stock")
      elsif pkg.available_stock != Float::INFINITY && pkg.available_stock < quantity
        errors.add(:quantity, "exceeds available stock for #{pkg.name}")
      end
    end
  end

  # ── Used by Cart#valid_for_checkout? before final order ──
  def valid_quantity?
    if product_id.present?
      return false unless product.present?
      chosen_variant = variant_attributes.presence

      # Common checks for all product types
      return false unless product.status == 'active' && product.vendor&.accepting_orders?
      return false if product.daily_quantity_limit_reached?(quantity)

      if product.has_real_variants?
        return false if chosen_variant.blank?
        product.can_fulfill?(quantity, variant: chosen_variant)
      else
        product.can_fulfill?(quantity)
      end
    elsif package_id.present?
      return false unless package.present?
      return false unless package.status == 'active' && package.vendor&.accepting_orders?
      return false if package.out_of_stock? ||
                     (package.available_stock != Float::INFINITY && package.available_stock < quantity)

      # Check component products' daily limits and availability
      package.package_products.each do |pp|
        product = pp.product
        next unless product
        return false unless product.status == 'active' && product.vendor&.accepting_orders?
        return false if product.daily_quantity_limit_reached?(quantity)
        if pp.variant_attributes.present? && product.variant_product?
          return false unless product.can_fulfill?(quantity, variant: pp.variant_attributes)
        else
          return false unless product.can_fulfill?(quantity)
        end
      end
      true
    else
      false
    end
  end

  # ── Stock reservation & release ──

  def reserve_stock!
    if product.present?
      product.reserve_stock!(quantity, variant_attributes.presence || nil)
    elsif package.present?
      package.reserve_stock!(quantity)
    end
  end

  def release_stock!
    if product.present?
      product.release_stock!(quantity, variant_attributes.presence || nil)
    elsif package.present?
      package.release_stock!(quantity)
    end
  end

  def release_and_destroy!
    release_stock!
    self.skip_stock_release_on_destroy = true
    destroy!
  end

  def destroy_for_checkout!
    self.skip_stock_release_on_destroy = true
    destroy!
  end

  private

  # ★ Set both base_price (list price) and price (final discounted price)
  def set_pricing
    if product.present?
      chosen_variant = variant_attributes.presence

      if chosen_variant.present? && product.variant_product?
        variant = product.find_variant(chosen_variant)
        if variant
          self.base_price = variant.price.to_f
          self.price = product.effective_price_for(variant.price.to_f)
        else
          self.base_price = product.price.to_f
          self.price = product.current_price
        end
      else
        self.base_price = product.price.to_f
        self.price = product.current_price
      end
    elsif package.present?
      self.base_price = package.price.to_f
      self.price = package.current_price
    end
  end

  def product_or_package_present
    unless product_id.present? || package_id.present?
      errors.add(:base, "Cart item must have either a product or a package")
    end
    if product_id.present? && package_id.present?
      errors.add(:base, "Cart item cannot reference both product and package")
    end
  end

  def variant_required_if_product_has_variants
    return unless product_id.present? && product.present?
    if product.has_real_variants? && variant_attributes.blank?
      errors.add(:variant_attributes, "must be selected for product with variants")
    end
  end

  def immutable_product_package_assignment
    if product_id_changed? && persisted?
      errors.add(:product_id, "cannot be changed after creation")
    end
    if package_id_changed? && persisted?
      errors.add(:package_id, "cannot be changed after creation")
    end
  end

  def unique_product_variant_or_package_in_cart
    return unless cart.present?

    if product_id.present?
      existing = cart.cart_items.where.not(id: id)
                      .where(product_id: product_id, variant_attributes: variant_attributes)
                      .exists?
      if existing
        errors.add(:base, "This product variant is already in the cart")
      end
    elsif package_id.present?
      existing = cart.cart_items.where.not(id: id)
                      .where(package_id: package_id)
                      .exists?
      if existing
        errors.add(:base, "This package is already in the cart")
      end
    end
  end

  def daily_quantity_limit_per_product
    return unless product_id.present? && product.present? && product.max_quantity_per_day.present?

    sold_today = product.today_quantity_sold
    active_cart_qty = CartItem.joins(:cart)
                              .where(product_id: product_id)
                              .where("cart_items.expires_at > ?", Time.current)
                              .where.not(id: id)
                              .sum(:quantity)

    total_after_change = sold_today + active_cart_qty + quantity

    if total_after_change > product.max_quantity_per_day
      remaining = product.max_quantity_per_day - sold_today - active_cart_qty
      errors.add(:quantity, "would exceed daily limit. Only #{[remaining, 0].max} left today.")
    end
  end

  def set_expiry
    if new_record? || quantity_changed? || price_changed? || variant_attributes_changed?
      self.expires_at = Time.current + RESERVATION_HOLD_MINUTES.minutes
    end
  end

  def stock_relevant_change?
    saved_change_to_quantity? || saved_change_to_variant_attributes?
  end

  def handle_stock_change
    old_qty = saved_change_to_quantity? ? saved_change_to_quantity[0] : quantity
    old_variant = saved_change_to_variant_attributes? ? saved_change_to_variant_attributes[0] : variant_attributes

    if old_qty.to_i > 0
      if product.present?
        product.release_stock!(old_qty, old_variant.presence || nil)
      elsif package.present?
        package.release_stock!(old_qty)
      end
    end

    reserve_stock!
  end
end