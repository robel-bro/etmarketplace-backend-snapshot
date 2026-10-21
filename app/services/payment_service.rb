# app/services/payment_service.rb

class PaymentService
  # ---------- existing order payment ----------
  def self.process(order:, idempotency_key: nil)
    # Prevent duplicate payment processing
    unless order.payment_status == 'pending'
      return { success: false, error: 'Order has already been processed for payment.' }
    end

    gateway_config = PaymentGateway.active.find_by(provider: order.payment_method)
    return { success: false, error: 'Payment method not available' } unless gateway_config

    # Create or find a PaymentLog for this order (idempotent)
    key = idempotency_key || SecureRandom.uuid
    payment_log = PaymentLog.find_or_initialize_by(order_id: order.id, idempotency_key: key)
    payment_log.update!(
      amount: order.total,
      payment_method: gateway_config.provider,
      status: 'pending',
      vendor_id: order.vendor_id
    )

    if gateway_config.provider == 'telebirr'
      gateway = Gateway::Telebirr.new(gateway_config)
      result = gateway.process(order)
      if result[:success]
        payment_log.update(transaction_id: result[:prepay_id])
        order.update(payment_transaction_id: result[:prepay_id])
        # ★ FIX: Transition order to paid after successful payment
        order.pay! unless order.payment_cash_on_delivery?
        { success: true, redirect_url: result[:checkout_url], prepay_id: result[:prepay_id] }
      else
        payment_log.update(status: 'failed', error_message: result[:error])
        { success: false, error: result[:error] }
      end
    else
      # Dynamic gateway (Chapa, etc.)
      result = Gateway::Dynamic.new(gateway_config).charge(order, nil)
      if result[:success]
        payment_log.update(transaction_id: result[:transaction_id])
        order.update(payment_transaction_id: result[:transaction_id])
        # ★ FIX: Transition order to paid after successful payment
        order.pay! unless order.payment_cash_on_delivery?
        { success: true, transaction_id: result[:transaction_id] }
      else
        payment_log.update(status: 'failed', error_message: result[:error])
        { success: false, error: result[:error] }
      end
    end
  end

  # ---------- membership subscription payment ----------
  def self.process_membership(vendor:, plan:, amount:, idempotency_key:, payment_method:)
    gateway_config = PaymentGateway.active.find_by(provider: payment_method)
    return { success: false, error: 'Payment method not available' } unless gateway_config

    # Idempotency – check for existing payment log with same key
    if idempotency_key.present?
      existing = PaymentLog.find_by(idempotency_key: idempotency_key)
      if existing && existing.status == 'completed'
        return { success: true, message: 'Payment already completed' }
      elsif existing
        return { success: false, error: 'Duplicate payment attempt' }
      end
    end

    # Record the payment attempt
    payment_log = PaymentLog.create!(
      vendor_id: vendor.id,
      membership_plan_id: plan.id,
      amount: amount,
      payment_method: payment_method,
      idempotency_key: idempotency_key,
      status: 'pending'
    )

    if gateway_config.provider == 'telebirr'
      gateway = Gateway::Telebirr.new(gateway_config)

      fake_order = Struct.new(:id, :total, :user).new(
        payment_log.id,
        amount,
        vendor.user
      )

      result = gateway.process(fake_order)

      if result[:success]
        payment_log.update(transaction_id: result[:prepay_id])
        { success: true, redirect_url: result[:checkout_url], prepay_id: result[:prepay_id] }
      else
        payment_log.update(status: 'failed', error_message: result[:error])
        { success: false, error: result[:error] }
      end
    else
      payment_log.update(status: 'failed', error_message: 'Unsupported gateway for membership')
      { success: false, error: 'Memberships are currently only available via Telebirr' }
    end
  end
end