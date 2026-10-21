# app/jobs/release_expired_cart_items_job.rb

class ReleaseExpiredCartItemsJob < ApplicationJob
  queue_as :default

  # Release all expired cart items across all users.
  # This is idempotent and safe to run frequently.
  def perform
    # Find all cart_ids that have at least one expired item
    expired_cart_ids = CartItem
                         .where("expires_at < ?", Time.current)
                         .distinct
                         .pluck(:cart_id)

    return if expired_cart_ids.empty?

    expired_cart_ids.each do |cart_id|
      cart = Cart.find_by(id: cart_id)
      next unless cart

      # Use the Cart#release_expired_items! method we added earlier
      # It handles stock release and item deletion atomically.
      cart.release_expired_items!
    rescue => e
      Rails.logger.error "Failed to release expired items for cart #{cart_id}: #{e.message}"
    end
  end
end