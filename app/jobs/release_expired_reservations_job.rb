# app/jobs/release_expired_reservations_job.rb

class ReleaseExpiredReservationsJob < ApplicationJob
  queue_as :default

  def perform
    # 1) Release expired cart items (this also releases any stock held by them)
    released_items = 0
    Cart.find_each do |cart|
      released_items += cart.release_expired_items!
    end

    # 2) Release orphaned expired reservations
    released_reservations = Reservation.release_expired!

    Rails.logger.info(
      "Expired hold cleanup: released #{released_items} cart item(s), " \
      "released #{released_reservations} reservation(s)"
    )
  end
end