# app/models/cart.rb

class Cart < ApplicationRecord
  belongs_to :user
  has_many :cart_items, dependent: :destroy
  has_many :products, through: :cart_items
  has_many :packages, through: :cart_items

  # Total price of all items in the cart
  def total_price
    cart_items.includes(:product, :package).sum { |item| (item.price || 0) * item.quantity }
  end

  # Check if all items are valid AND bulk MOQ is satisfied
  def valid_for_checkout?
    cart_items.all?(&:valid_quantity?) && bulk_products_below_minimum.empty?
  end

  # Returns an array of human-readable error messages
  def checkout_errors
    errors = cart_items.reject(&:valid_quantity?).map do |item|
      name = item.product&.title || item.package&.name || "Item ##{item.id}"
      "#{name} is out of stock or quantity not available"
    end

    bulk_products_below_minimum.each do |product_id, data|
      product = Product.find(product_id)
      errors << "#{product.title} requires a minimum of #{data[:minimum]} units (#{data[:needed]} more needed)"
    end
    errors
  end

  # Returns a hash of { product_id => { needed: X, minimum: Y } } for products
  # that don't yet meet the minimum bulk quantity
  def bulk_products_below_minimum
    result = {}
    product_ids = cart_items.pluck(:product_id).compact.uniq

    Product.where(id: product_ids, bulk_enabled: true)
           .where.not(minimum_bulk_quantity: nil)
           .each do |product|
      total_in_cart = cart_items.where(product_id: product.id).sum(:quantity)

      if total_in_cart < product.minimum_bulk_quantity
        result[product.id] = {
          needed: product.minimum_bulk_quantity - total_in_cart,
          minimum: product.minimum_bulk_quantity
        }
      end
    end

    result
  end

  # Clear cart and release all reserved stock.
  # Used when user empties cart or cancels checkout.
  def clear!
    ActiveRecord::Base.transaction do
      cart_items.each(&:release_and_destroy!)
    end
  end

  # Clear cart after successful checkout WITHOUT releasing stock.
  # The order now owns the reservation/stock.
  def clear_after_checkout!
    ActiveRecord::Base.transaction do
      cart_items.each(&:destroy_for_checkout!)
    end
  end

  # Background job: release expired items.
  # Should run every 1-2 minutes.
  # Returns the number of items released.
  def release_expired_items!
    expired_items = cart_items.where("expires_at < ?", Time.current)
    return 0 if expired_items.empty?

    count = expired_items.count

    ActiveRecord::Base.transaction do
      expired_items.each(&:release_and_destroy!)
    end

    count
  end
end