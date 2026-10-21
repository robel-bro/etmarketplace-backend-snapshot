# app/services/funds_release_service.rb
class FundsReleaseService
  # Call this service every day (cron) to release funds for orders whose return window has expired.
  def self.release_expired_orders
    orders = Order.where(status: :delivered)
                  .where('delivered_at <= ?', Time.current)
                  .where(return_window_days: ..0)   # delivered_at + window already past? We'll check manually
                  .select { |order| order.return_window_expired? }

    released = 0
    orders.each do |order|
      next if FinancialLedger.exists?(order: order, transaction_type: 'funds_release_seller')

      begin
        FinancialLedgerService.release_funds(order)
        order.complete!   # transition to completed
        released += 1
      rescue => e
        Rails.logger.error "Funds release failed for Order ##{order.id}: #{e.message}"
      end
    end
    released
  end
end