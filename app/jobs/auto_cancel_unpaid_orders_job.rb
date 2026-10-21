# app/jobs/auto_cancel_unpaid_orders_job.rb

class AutoCancelUnpaidOrdersJob < ApplicationJob
  queue_as :default

  # Orders older than this with pending payment will be cancelled
  PAYMENT_TIMEOUT_MINUTES = 30

  def perform
    expired_orders = Order
      .where(status: :pending)
      .where(payment_status: :pending)
      .where.not(payment_method_enum: :cash_on_delivery)
      .where("orders.created_at < ?", PAYMENT_TIMEOUT_MINUTES.minutes.ago)

    expired_orders.find_each do |order|
      next unless order.may_cancel?

      # Cancel restores stock and zeros financials if not paid
      order.cancel!

      # Optional: notify user
      NotificationService.notify(order.user, :order_auto_cancelled, { order_id: order.id })
    end
  end
end