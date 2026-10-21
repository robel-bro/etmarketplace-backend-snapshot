# app/models/checkout_group.rb

class CheckoutGroup < ApplicationRecord
  belongs_to :user
  has_many :orders, foreign_key: :checkout_group_id, dependent: :nullify

  enum :status, {
    pending: 0,       # initial state after creation
    paid: 1,          # all orders paid
    accepted: 2,      # all sellers accepted
    dispatched: 3,    # delivery request created
    delivered: 4,     # all items delivered
    partial: 5,       # some orders cancelled/refunded
    cancelled: 6      # entire group cancelled
  }

  validates :consolidated_shipping_cost, :buyer_shipping_cost, :total_subsidy,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Build a manifest of all items in the group (for dispatch)
  def manifest
    orders.includes(:line_items, vendor: :user).map do |order|
      vendor = order.vendor
      {
        vendor_id: order.vendor_id,
        vendor_name: vendor.business_name,
        pickup_address: vendor.business_address,
        pickup_phone: vendor.phone,
        pickup_lat: vendor.business_lat,
        pickup_lng: vendor.business_lng,
        ready: vendor.respond_to?(:pickup_ready?) ? vendor.pickup_ready? : false,
        items: order.line_items.map do |li|
          product = li.product
          next unless product  # Skip if product missing (shouldn't happen)
          {
            product_id: product.id,
            title: product.title,
            quantity: li.quantity,
            price: li.price,
            image_url: product.first_image_url,
            weight_kg: product.weight_kg,
            dimensions: {
              length: product.length_cm,
              width: product.width_cm,
              height: product.height_cm
            }
          }
        end.compact
      }
    end
  end

  # Total weight of all items in the group (handles nil weights)
  def total_weight_kg
    orders.joins(line_items: :product)
          .where.not(products: { weight_kg: nil })
          .sum('line_items.quantity * COALESCE(products.weight_kg, 0)')
  end

  # Total item count across all orders
  def total_items_count
    orders.sum { |order| order.line_items.sum(:quantity) }
  end

  # Total value of all orders in the group
  def total_value
    orders.sum(:total)
  end
end