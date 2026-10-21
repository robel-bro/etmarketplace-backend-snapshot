# app/controllers/webhooks/payments_controller.rb (world‑class hardened)
class Webhooks::PaymentsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_authentication

  # POST /webhooks/payments
  def create
    provider = request.headers['X-Gateway-Provider'] || params[:provider]
    unless provider
      render json: { error: 'Provider not specified' }, status: :unprocessable_entity
      return
    end

    gateway_config = PaymentGateway.active.find_by(provider: provider)
    unless gateway_config
      render json: { error: 'Unknown provider' }, status: :unprocessable_entity
      return
    end

    unless verify_signature_for(provider, gateway_config)
      render json: { error: 'Invalid signature' }, status: :forbidden
      return
    end

    transaction_id = params[:transaction_id] || params[:trans_id]
    reference      = params[:reference] || params[:out_trade_no]
    status         = params[:status]&.downcase

    # Find or create the PaymentLog atomically
    log = find_or_create_log(provider, transaction_id, reference, params)

    # Lock the log row to prevent concurrent processing
    log.with_lock do
      # Idempotent return if already completed or failed
      if log.status.in?(%w[completed failed])
        head :ok and return
      end

      if log.order_id.nil? && log.vendor_id.present?
        process_membership_webhook!(log, status, transaction_id, params)
      else
        process_order_webhook!(log, status, transaction_id, params)
      end
    end

    head :ok
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Payment webhook RecordInvalid: #{e.message}"
    head :unprocessable_entity
  rescue => e
    Rails.logger.error "Payment webhook unexpected error: #{e.message}"
    head :internal_server_error
  end

  private

  def verify_signature_for(provider, gateway_config)
    case provider.to_s.downcase
    when 'telebirr'
      Gateway::Telebirr.verify_notification(params.to_unsafe_h, gateway_config)
    else
      secret = gateway_config.webhook_secret
      return true unless secret.present?

      signature = request.headers['X-Gateway-Signature']
      return false unless signature.present?

      expected = OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)
      ActiveSupport::SecurityUtils.secure_compare(signature, expected)
    end
  end

  def find_or_create_log(provider, transaction_id, reference, params)
    # Try to find an existing log by transaction ID first (stronger)
    log = PaymentLog.find_by(transaction_id: transaction_id) if transaction_id.present?
    return log if log

    # Then try idempotency key (reference)
    log = PaymentLog.find_by(idempotency_key: reference) if reference.present?
    return log if log

    # If neither found, create a new log entry for this webhook.
    # This is a safety net – normally the log should already exist from checkout.
    PaymentLog.create!(
      transaction_id: transaction_id,
      idempotency_key: reference || SecureRandom.uuid,
      payment_method: provider,
      amount: params[:amount] || 0,
      status: 'pending',
      raw_data: params.to_unsafe_h
    )
  rescue ActiveRecord::RecordNotUnique
    # Race condition: another request created the log between find and create
    PaymentLog.find_by!(transaction_id: transaction_id) || PaymentLog.find_by!(idempotency_key: reference)
  end

  def process_membership_webhook!(log, status, transaction_id, params)
    if status.in?(%w[success completed paid])
      ActiveRecord::Base.transaction do
        log.update!(status: 'completed', transaction_id: transaction_id || log.transaction_id)

        vendor = Vendor.find_by(id: log.vendor_id)
        plan   = MembershipPlan.find_by(id: log.membership_plan_id)

        if vendor && plan
          vendor.assign_membership_plan(plan)
          FinancialLedgerService.record_membership(vendor, log.amount)
        end
      end
    else
      log.update!(status: 'failed', error_message: params[:error] || "Gateway status: #{status}")
    end
  end

  def process_order_webhook!(log, status, transaction_id, params)
    primary_order = log.order
    return unless primary_order

    checkout_group = primary_order.checkout_group

    if status.in?(%w[success completed paid])
      ActiveRecord::Base.transaction do
        orders = if checkout_group
                   checkout_group.orders.order(:id).lock
                 else
                   [primary_order]
                 end

        orders.each do |order|
          next if order.payment_completed?

          if order.respond_to?(:pay!)
            order.pay! if order.may_pay?
          else
            order.update!(payment_status: :completed)
          end
          order.update!(payment_transaction_id: transaction_id || log.transaction_id)
        end

        checkout_group&.update!(status: :paid)

        log.update!(status: 'completed', transaction_id: transaction_id || log.transaction_id)

        orders.each do |order|
          FinancialLedgerService.record_payment(order, order.total, log.payment_method)
        end

        orders.each do |order|
          OrderAcceptanceJob.perform_later(order.id)
        end
      end
    elsif status.in?(%w[failed cancelled expired])
      ActiveRecord::Base.transaction do
        log.update!(status: 'failed', error_message: params[:error] || "Gateway status: #{status}")

        orders = checkout_group ? checkout_group.orders : [primary_order]
        orders.each do |order|
          next if order.payment_completed?
          if order.respond_to?(:fail_payment!)
            order.fail_payment! if order.may_fail_payment?
          else
            order.update!(payment_status: :failed)
          end
        end
      end
    end
  end
end