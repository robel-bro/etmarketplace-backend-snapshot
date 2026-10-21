# app/jobs/order_acceptance_job.rb

class OrderAcceptanceJob < ApplicationJob
  queue_as :default

  # Deadline in minutes (default 60)
  DEADLINE_MINUTES = ENV.fetch('ORDER_ACCEPTANCE_DEADLINE_MINUTES', 60).to_i

  def perform(order_id, action = :schedule, minutes_left = nil)
    order = Order.find(order_id)
    return unless order.pending_acceptance?

    case action.to_sym
    when :schedule
      schedule_reminders_and_cancel(order)
    when :reminder
      send_reminder(order, minutes_left)
    when :auto_cancel
      auto_cancel(order)
    end
  rescue ActiveRecord::RecordNotFound
    # order may have been deleted; ignore
  end

  private

  def schedule_reminders_and_cancel(order)
    # Idempotency: skip if already scheduled
    return if order.order_events.exists?(event_type: 'acceptance_scheduled')

    deadline = order.acceptance_deadline

    # 1. First reminder – 15 minutes before deadline
    first_reminder_time = deadline - 15.minutes
    if first_reminder_time > Time.current
      self.class.set(wait_until: first_reminder_time).perform_later(order.id, :reminder, 15)
    else
      send_reminder(order, 15)
    end

    # 2. Final alarm – 5 minutes before deadline
    final_alarm_time = deadline - 5.minutes
    if final_alarm_time > Time.current
      self.class.set(wait_until: final_alarm_time).perform_later(order.id, :reminder, 5)
    else
      send_reminder(order, 5) if deadline > Time.current
    end

    # 3. Auto‑cancel exactly at deadline
    self.class.set(wait_until: deadline).perform_later(order.id, :auto_cancel)

    # Mark scheduled to prevent duplicate scheduling
    order.order_events.create!(
      event_type: 'acceptance_scheduled',
      actor: nil,
      status_from: order.status,
      status_to: order.status
    )
  rescue => e
    Rails.logger.error "Failed to schedule acceptance job for order #{order.id}: #{e.message}"
  end

  def send_reminder(order, minutes_left)
    seller = order.vendor.user
    NotificationService.notify(seller, :order_acceptance_reminder, {
      order_id: order.id,
      minutes_left: minutes_left,
      deadline: order.acceptance_deadline
    })
  end

  def auto_cancel(order)
    # Lock the order to prevent race conditions
    order = Order.lock.find(order.id)
    return unless order.pending_acceptance?

    # Capture refund amount BEFORE changing financials (because reject! may zero totals)
    refund_amount = order.total.to_f if order.payment_completed?

    # Bypass the deadline guard with transient flag
    order.auto_cancel_mode = true
    order.reject!

    # Refund only if payment was actually captured and amount > 0
    if refund_amount.present? && refund_amount > 0
      begin
        RefundService.new(order).full_refund!
      rescue => e
        Rails.logger.error "Failed to refund order #{order.id}: #{e.message}"
      end
    end

    # Notify both parties
    NotificationService.notify(order.user, :order_auto_cancelled, { order_id: order.id })
    NotificationService.notify(order.vendor.user, :order_auto_cancelled_seller, { order_id: order.id })
  rescue AASM::InvalidTransition => e
    Rails.logger.warn "Order ##{order.id} could not be auto-cancelled: #{e.message}"
  rescue => e
    Rails.logger.error "Error in auto_cancel for order #{order.id}: #{e.message}"
  end
end