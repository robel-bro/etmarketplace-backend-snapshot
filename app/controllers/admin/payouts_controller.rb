# app/controllers/admin/payouts_controller.rb

class Admin::PayoutsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_payout, only: [:update, :approve, :reject, :mark_completed, :mark_processing, :retry_telebirr]

  WITHHOLDING_TAX_RATE = 0.02

  # GET /admin/payouts
  def index
    payouts = Payout.includes(:vendor).order(created_at: :desc)
    payouts = payouts.where(status: params[:status]) if params[:status].present?
    payouts = payouts.where(payout_method: params[:method]) if params[:method].present?

    page = (params[:page] || 1).to_i
    per_page = 50
    total = payouts.count
    paginated = payouts.offset((page - 1) * per_page).limit(per_page)

    data = paginated.map do |p|
      {
        id: p.id,
        vendor: { id: p.vendor.id, business_name: p.vendor.business_name },
        amount: p.amount.to_f,
        status: p.status,
        payout_method: p.payout_method,
        created_at: p.created_at,
        recipient_details: p.recipient_details
      }
    end

    render json: { payouts: data, total: total }
  end

  # POST /admin/payouts
  def create
    vendor = Vendor.find(params[:vendor_id])
    orders = vendor.orders.where(payment_status: :completed, status: :delivered)
                    .where.not(id: OrderPayout.select(:order_id))

    gross_earnings = orders.sum { |o| o.seller_earnings }
    wht = (gross_earnings * WITHHOLDING_TAX_RATE).round(2)
    net_amount = gross_earnings - wht

    if net_amount <= 0
      return render json: { error: 'No positive payout amount for selected orders.' }, status: :unprocessable_entity
    end

    payout = vendor.payouts.new(
      amount: net_amount,
      gross_amount: gross_earnings,
      tax_withheld: wht,
      period_start: params[:period_start],
      period_end: params[:period_end],
      status: :pending,
      payout_method: vendor.payout_method,
      recipient_details: vendor.payout_details_snapshot
    )

    if payout.save
      orders.each { |order| OrderPayout.create!(order: order, payout: payout) }
      ::AdminAuditLog.log(current_user, 'payout_created', payout, {
        vendor: vendor.business_name,
        gross_amount: gross_earnings,
        tax_withheld: wht,
        net_amount: net_amount
      })
      render json: payout, status: :created
    else
      render json: { errors: payout.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Vendor not found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # PATCH/PUT /admin/payouts/:id
  # Only allow updating notes/period, not status directly
  def update
    if @payout.status != 'pending'
      return render json: { error: 'Cannot update a payout that is not pending' }, status: :unprocessable_entity
    end

    if @payout.update(payout_update_params)
      render json: @payout
    else
      render json: { errors: @payout.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /admin/payouts/:id/approve
  def approve
    if @payout.status != 'pending'
      return render json: { error: "Only pending payouts can be approved" }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      @payout.update!(status: :processing)
      ::AdminAuditLog.log(current_user, 'payout_approved', @payout, {
        vendor: @payout.vendor.business_name,
        amount: @payout.amount
      })
    end

    render json: { message: "Payout ##{@payout.id} marked as processing." }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /admin/payouts/bulk_process_telebirr
  def bulk_process_telebirr
    payouts = Payout.where(status: :pending, payout_method: 'telebirr').includes(:vendor)
    if payouts.empty?
      return render json: { message: 'No pending Telebirr payouts' }, status: :unprocessable_entity
    end

    success = 0
    failures = 0
    payouts.each do |payout|
      begin
        gateway_config = PaymentGateway.active.find_by(provider: 'telebirr')
        if gateway_config && payout.recipient_details['telebirr_account'].present?
          result = Gateway::Telebirr.transfer(
            to: payout.recipient_details['telebirr_account'],
            amount: payout.amount,
            reference: "payout_#{payout.id}"
          )
          if result[:success]
            payout.update!(gateway_reference: result[:transaction_id], status: :processing)
            success += 1
          else
            failures += 1
          end
        else
          failures += 1
        end
      rescue => e
        Rails.logger.error "Telebirr bulk payout #{payout.id} failed: #{e.message}"
        failures += 1
      end
    end
    render json: { success: success, failures: failures, message: "Processed #{success} successfully, #{failures} failed." }
  end

  # GET /admin/payouts/bulk_bank_export
  def bulk_bank_export
    payouts = Payout.where(status: :pending, payout_method: 'bank').includes(:vendor)
    if payouts.empty?
      return render json: { error: 'No pending bank payouts' }, status: :unprocessable_entity
    end
    csv_data = PayoutService.generate_bank_file(payouts)
    payouts.update_all(status: :processing)
    send_data csv_data, filename: "bank_payouts_#{Date.today}.csv", type: 'text/csv'
  end

  # POST /admin/payouts/:id/reject
  def reject
    if @payout.status == 'pending'
      @payout.update!(status: 'rejected')
      FinancialLedgerService.record_payout_rejected(@payout)
      render json: { message: "Payout rejected. Funds returned to seller's available balance." }
    else
      render json: { error: "Only pending payouts can be rejected" }, status: :unprocessable_entity
    end
  end

  # POST /admin/payouts/:id/mark_completed
  def mark_completed
    if @payout.status == 'processing'
      complete_payout(@payout)
      render json: { message: "Payout ##{@payout.id} completed." }
    else
      render json: { error: "Only processing payouts can be completed" }, status: :unprocessable_entity
    end
  end

  # POST /admin/payouts/:id/mark_processing
  def mark_processing
    if @payout.status == 'pending'
      @payout.update!(status: 'processing')
      render json: { message: "Payout ##{@payout.id} marked as processing." }
    else
      render json: { error: "Only pending payouts can be moved to processing" }, status: :unprocessable_entity
    end
  end

  # POST /admin/payouts/:id/retry_telebirr
  def retry_telebirr
    unless @payout.payout_method == 'telebirr' && %w[pending failed].include?(@payout.status)
      return render json: { error: "Invalid payout for Telebirr retry" }, status: :unprocessable_entity
    end
    gateway_config = PaymentGateway.active.find_by(provider: 'telebirr')
    unless gateway_config
      return render json: { error: "Telebirr gateway not configured" }, status: :unprocessable_entity
    end
    phone = @payout.recipient_details['telebirr_account']
    unless phone.present?
      return render json: { error: "No Telebirr account in recipient details" }, status: :unprocessable_entity
    end
    result = Gateway::Telebirr.transfer(to: phone, amount: @payout.amount, reference: "payout_#{@payout.id}_retry")
    if result[:success]
      @payout.update!(gateway_reference: result[:transaction_id], status: :processing)
      render json: { message: "Telebirr payout retry successful." }
    else
      render json: { error: "Telebirr retry failed: #{result[:error]}" }, status: :unprocessable_entity
    end
  end

  private

  def set_payout
    @payout = Payout.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Payout not found' }, status: :not_found
    return false
  end

  def complete_payout(payout)
    ActiveRecord::Base.transaction do
      payout.update!(status: :paid, processed_at: Time.current)

      if payout.vendor.user
        Notification.create!(
          user: payout.vendor.user,
          title: "Payout Processed",
          body: "Your payout of ETB #{payout.amount} (net after 2% WHT) has been approved.",
          notification_type: "payout_paid",
          metadata: { payout_id: payout.id }
        )
      end

      # Double‑entry ledger
      FinancialLedgerService.record_payout_completed(payout)

      if payout.respond_to?(:tax_withheld) && payout.tax_withheld.to_f > 0
        FinancialLedgerService.record_tax_withheld(payout)
      end

      # Audit log – use ::AdminAuditLog to escape the Admin namespace
      ::AdminAuditLog.log(current_user, 'payout_completed', payout, {
        vendor: payout.vendor.business_name,
        net_amount: payout.amount,
        tax_withheld: payout.respond_to?(:tax_withheld) ? payout.tax_withheld : 0
      })
    end
  end

  def payout_update_params
    params.permit(:period_start, :period_end, :notes)
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'payouts' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('payouts')
    head :forbidden
    false
  end
end