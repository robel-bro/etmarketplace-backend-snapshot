class ReservationService
  # Reserve a quantity of a product for a user. Returns the reservation or raises.
  def self.reserve!(user:, product:, quantity: 1)
    raise "Quantity must be positive" if quantity < 1

    Reservation.transaction do
      # Lock the product row to prevent overselling
      locked_product = Product.lock.find(product.id)

      # Check available stock (uses the hardened method – bulk/variant aware)
      available = locked_product.available_stock
      if available < quantity
        raise ActiveRecord::RecordInvalid.new(
          ActiveModel::Errors.new(locked_product).tap { |e| e.add(:stock, "Only #{available} left") }
        )
      end

      # Check for existing active reservation for this user and product
      existing = Reservation.active.find_by(user_id: user.id, product_id: product.id)
      if existing
        # Update quantity and extend expiry
        existing.update!(quantity: existing.quantity + quantity, expires_at: 15.minutes.from_now)
      else
        Reservation.create!(
          user_id: user.id,
          product_id: product.id,
          quantity: quantity,
          expires_at: 15.minutes.from_now
        )
      end

      # Update the cached stock_reserved counter (recalculate from all active reservations)
      locked_product.reset_stock_reserved!
    end
  end

  # Release a specific reservation (e.g., when cart item removed)
  def self.release!(reservation)
    ActiveRecord::Base.transaction do
      reservation.destroy!
      Product.reset_stock_reserved!(reservation.product_id)
    end
  end

  # Convert reservations to order when order is placed
  def self.confirm_order!(user:, order:)
    Reservation.active.where(user_id: user.id).update_all(order_id: order.id, expires_at: nil)
    # No need to adjust stock_reserved because the order now owns the stock;
    # future queries will exclude these reservations (they have order_id set).
  end
end