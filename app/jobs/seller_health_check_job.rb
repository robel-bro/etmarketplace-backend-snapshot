class SellerHealthCheckJob < ApplicationJob
  queue_as :default

  def perform
    Vendor.approved.find_each do |vendor|
      vendor.update_order_stats!    # recompute health metrics
      vendor.check_health!          # evaluate rules and suspend if needed
    end
  end
end