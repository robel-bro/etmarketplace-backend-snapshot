# app/services/refund_service.rb

class RefundService
  attr_reader :order, :return_request

  def initialize(order, return_request: nil)
    @order = order
    @return_request = return_request
  end

  # ── Full refund (used for cancellations) ──
  def full_refund!
    return true if order.payment_refunded?

    refund_amount = order.total
    commission_before = order.commission_amount.to_f

    ActiveRecord::Base.transaction do
      process_gateway_refund(refund_amount, "order_#{order.id}_full_refund")

      order.update!(payment_status: :refunded, refunded_amount: refund_amount)

      # Cancel order (this restores stock via handle_cancellation and may zero financials)
      order.cancel! if order.may_cancel?

      # Clawback seller commission using the captured amount before cancellation
      clawback_seller_commission!(commission_before) if commission_before > 0

      # Log event using public method or direct order_events create
      order.order_events.create!(
        event_type: :full_refund_processed,
        actor: nil,
        status_from: order.status,
        status_to: order.status
      ) rescue nil

      record_refund_in_ledger(refund_amount)
    end
    order.payment_refunded?
  rescue => e
    Rails.logger.error "Full refund failed for order #{order.id}: #{e.message}"
    false
  end

  # ── Refund for a return request ──
  def process!
    return false unless return_request.present?
    return true if order.payment_refunded?

    refund_amount = calculate_return_refund
    commission_before = order.commission_amount.to_f

    ActiveRecord::Base.transaction do
      process_gateway_refund(refund_amount, "return_#{return_request.id}_refund")

      order.update!(payment_status: :refunded, refunded_amount: refund_amount)

      # Mark order as returned (if possible) and restore stock exactly once
      order.return! if order.may_return?
      order.restore_stock unless order.status == 'cancelled'

      # Clawback seller commission using captured amount
      clawback_seller_commission!(commission_before) if commission_before > 0

      # Charge return shipping to liable party
      if return_request.liability == 'seller' && return_request.return_shipping_cost.to_f > 0
        deduct_shipping_from_seller(return_request.return_shipping_cost)
      end

      order.order_events.create!(
        event_type: :return_refund_processed,
        actor: nil,
        status_from: order.status,
        status_to: order.status
      ) rescue nil

      record_refund_in_ledger(refund_amount)

      # Mark return request as completed only if it has been received.
      # If not received, the admin controller should ensure it is received before processing refund.
      return_request.complete! if return_request.received?
    end
    order.payment_refunded?
  rescue => e
    Rails.logger.error "Return refund failed for order #{order.id}: #{e.message}"
    false
  end

  private

  def calculate_return_refund
    base = order.total
    restocking = order.restocking_fee_percent.to_f > 0 ? (base * order.restocking_fee_percent / 100.0).round(2) : 0
    return_shipping = return_request&.return_shipping_cost.to_f
    buyer_pays = return_request&.liability == 'buyer' || order.return_shipping_responsibility == 'buyer'
    return_shipping = 0 unless buyer_pays
    [base - restocking - return_shipping, 0].max
  end

  def process_gateway_refund(amount, idempotency_key)
    return true if order.payment_cash_on_delivery?

    provider = case order.payment_method_enum
               when 'telebirr' then 'telebirr'
               when 'chapa'    then 'chapa'
               else nil
               end
    return true unless provider

    gateway = PaymentGateway.active.find_by(provider: provider)
    return true unless gateway

    result = gateway.refund(order.payment_transaction_id, amount, idempotency_key)
    result[:success]
  rescue => e
    Rails.logger.warn "Gateway refund skipped for order #{order.id}: #{e.message}"
    true   # proceed with manual refund
  end

  def deduct_shipping_from_seller(amount)
    # Use FinancialLedgerService to record a penalty if available
    if defined?(FinancialLedgerService) && FinancialLedgerService.respond_to?(:record_seller_shipping_penalty)
      FinancialLedgerService.record_seller_shipping_penalty(order, amount)
    else
      Rails.logger.warn "[RefundService] FinancialLedgerService.record_seller_shipping_penalty not available"
    end
  end

  def clawback_seller_commission!(amount)
    return unless amount.to_f > 0

    if defined?(FinancialLedgerService) && FinancialLedgerService.respond_to?(:record_refund_clawback)
      FinancialLedgerService.record_refund_clawback(order, amount)
    else
      Rails.logger.warn "[RefundService] FinancialLedgerService.record_refund_clawback not available; commission clawback skipped for order #{order.id}"
    end
  end

  def record_refund_in_ledger(amount)
    if defined?(FinancialLedgerService) && FinancialLedgerService.respond_to?(:record_refund)
      FinancialLedgerService.record_refund(order, amount)
    else
      Rails.logger.warn "FinancialLedgerService.record_refund not available"
    end
  end
end