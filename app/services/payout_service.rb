# app/services/payout_service.rb

class PayoutService
  # Minimum payout amount is now configurable from Settings.
  def self.min_payout
    setting = Setting.get('payout_minimum')
    amount = setting.to_f
    amount > 0 ? amount : 10.0
  end

  def initialize(vendor)
    @vendor = vendor
  end

  # ── Summary for seller dashboard ──
  def summary
    available = @vendor.available_balance
    payouts   = @vendor.payouts
    pending   = payouts.where(status: :pending).sum(:amount)
    paid      = payouts.where(status: :paid).sum(:amount)
    held      = payouts.where(held: true).sum(:amount)

    total_earned = available + paid + pending + held

    {
      total_earned: total_earned.to_f,
      pending:      pending.to_f,
      available:    available.to_f,
      paid:         paid.to_f,
      held:         held.to_f
    }
  end

  # ── Request a payout of the full available balance ──
  def request_payout(period_start: nil, period_end: nil)
    available = @vendor.available_balance
    min_amount = self.class.min_payout

    if available < min_amount
      raise StandardError, "Minimum payout amount is #{min_amount} Birr. Your available balance is #{available} Birr."
    end

    # Idempotency: prevent multiple pending payouts for same vendor
    if @vendor.payouts.where(status: [:pending, :processing]).exists?
      raise StandardError, "You already have a pending or processing payout request."
    end

    ActiveRecord::Base.transaction do
      payout = @vendor.payouts.create!(
        amount:            available,
        status:            :pending,
        payout_method:     @vendor.payout_method,
        recipient_details: @vendor.payout_details_snapshot,
        period_start:      period_start || Time.current.beginning_of_month,
        period_end:        period_end   || Time.current.end_of_month
      )

      # Link every eligible order to this payout (prevents double‑payout)
      eligible_orders_ids = eligible_orders.pluck(:id)
      eligible_orders_ids.each do |order_id|
        OrderPayout.create!(order_id: order_id, payout: payout)
      end

      # Double‑entry ledger: Debit Seller Receivable, Credit Payout Payable
      FinancialLedgerService.record_payout_created(payout)

      # Optionally trigger automatic Telebirr transfer
      if @vendor.payout_telebirr?
        process_telebirr_payout(payout)
      end

      payout
    end
  rescue StandardError => e
    raise e
  end

  # ── Admin marks a payout as completed ──
  def self.mark_completed(payout, gateway_reference: nil)
    ActiveRecord::Base.transaction do
      payout.update!(
        status:            :paid,
        gateway_reference: gateway_reference,
        processed_at:      Time.current
      )
      FinancialLedgerService.record_payout_completed(payout)

      if payout.respond_to?(:tax_withheld) && payout.tax_withheld.to_f > 0
        FinancialLedgerService.record_tax_withheld(payout)
      end
    end
  end

  # ── Generate a CSV bulk bank file for pending bank payouts ──
  def self.generate_bank_file(payouts)
    require 'csv'
    CSV.generate(headers: true) do |csv|
      csv << ['Account Number', 'Beneficiary Name', 'Amount (Birr)', 'Reference']
      payouts.each do |p|
        details = p.recipient_details
        csv << [
          details['bank_account_number'],
          details['bank_name'] || p.vendor.business_name,
          p.amount.to_f,
          "Payout##{p.id}"
        ]
      end
    end
  end

  private

  # Eligible orders: delivered/completed, not already linked to a payout.
  def eligible_orders
    @vendor.orders
           .where(payment_status: :completed)
           .where(status: [:delivered, :completed])
           .where.not(id: OrderPayout.select(:order_id))
           .where('commission_amount IS NOT NULL AND commission_amount >= 0')
           .where("seller_earning IS NOT NULL AND seller_earning > 0")
  end

  # ── Initiate a single Telebirr payout ──
  def process_telebirr_payout(payout)
    gateway_config = PaymentGateway.active.find_by(provider: 'telebirr')
    return unless gateway_config

    phone = payout.recipient_details['telebirr_account']
    unless phone.present?
      Rails.logger.warn "Telebirr payout #{payout.id} failed: no telebirr_account in snapshot"
      return
    end

    result = Gateway::Telebirr.transfer(
      to:        phone,
      amount:    payout.amount,
      reference: "payout_#{payout.id}"
    )

    if result[:success]
      payout.update!(gateway_reference: result[:transaction_id], status: :processing)
    else
      Rails.logger.error "Telebirr payout #{payout.id} failed: #{result[:error]}"
      # Leave status as :pending so admin can retry
    end
  rescue => e
    Rails.logger.error "Telebirr payout #{payout.id} exception: #{e.message}"
  end
end