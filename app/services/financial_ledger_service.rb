# app/services/financial_ledger_service.rb

class FinancialLedgerService
  ACCOUNTS = {
    cash_bank:            'CASH_BANK',
    liability_uncleared:  'LIABILITY_UNCLEARED',
    seller_receivable:    'SELLER_RECEIVABLE',
    payout_payable:       'PAYOUT_PAYABLE',
    commission_revenue:   'COMMISSION_REVENUE',
    service_fee_revenue:  'SERVICE_FEE_REVENUE',
    vat_payable:          'VAT_PAYABLE',
    wht_payable:          'WHT_PAYABLE',
    membership_revenue:   'MEMBERSHIP_REVENUE',
    logistics_payable:    'LOGISTICS_PAYABLE',
    refunds_receivable:   'REFUNDS_RECEIVABLE'
  }.freeze

  # ── Customer payment received (webhook confirmation) ──
  def self.record_payment(order, amount, gateway_name)
    create_entry(
      debit:  ACCOUNTS[:cash_bank],
      credit: ACCOUNTS[:liability_uncleared],
      amount: amount,
      type:   'customer_payment',
      desc:   "Payment received for Order ##{order.id} via #{gateway_name}",
      order:  order
    )
  end

  # ── Membership subscription fee ──
  def self.record_membership(vendor, amount)
    create_entry(
      debit:  ACCOUNTS[:cash_bank],
      credit: ACCOUNTS[:membership_revenue],
      amount: amount,
      type:   'membership_revenue',
      desc:   "Membership payment from #{vendor.business_name}",
      vendor: vendor
    )
  end

  # ── Release funds after return window expires ──
  def self.release_funds(order)
    raise ArgumentError, "Order must be delivered and return window expired" unless order.return_window_expired?

    ActiveRecord::Base.transaction do
      seller_earning = order.seller_earnings
      commission = order.commission_amount || 0
      service_fee = order.service_fee || 0
      vat_amount  = order.vat_amount || 0

      # Seller earning: Debit Liability → Credit Seller Receivable
      create_entry(
        debit:  ACCOUNTS[:liability_uncleared],
        credit: ACCOUNTS[:seller_receivable],
        amount: seller_earning,
        type:   'funds_release_seller',
        desc:   "Seller earnings released for Order ##{order.id}",
        order:  order
      )
      # Commission: Debit Liability → Credit Commission Revenue
      create_entry(
        debit:  ACCOUNTS[:liability_uncleared],
        credit: ACCOUNTS[:commission_revenue],
        amount: commission,
        type:   'funds_release_commission',
        desc:   "Commission released for Order ##{order.id}",
        order:  order
      )
      # Service fee: Debit Liability → Credit Service Fee Revenue
      create_entry(
        debit:  ACCOUNTS[:liability_uncleared],
        credit: ACCOUNTS[:service_fee_revenue],
        amount: service_fee,
        type:   'funds_release_service_fee',
        desc:   "Service fee released for Order ##{order.id}",
        order:  order
      )
      # VAT: Debit Liability → Credit VAT Payable
      create_entry(
        debit:  ACCOUNTS[:liability_uncleared],
        credit: ACCOUNTS[:vat_payable],
        amount: vat_amount,
        type:   'funds_release_vat',
        desc:   "VAT released for Order ##{order.id}",
        order:  order
      )
    end
  end

  # ── Payout created (staged for payment) ──
  def self.record_payout_created(payout)
    create_entry(
      debit:  ACCOUNTS[:seller_receivable],
      credit: ACCOUNTS[:payout_payable],
      amount: payout.amount,
      type:   'payout_created',
      desc:   "Payout ##{payout.id} to #{payout.vendor.business_name}",
      payout: payout
    )
  end

  # ── Payout completed (money left bank/wallet) ──
  def self.record_payout_completed(payout)
    create_entry(
      debit:  ACCOUNTS[:payout_payable],
      credit: ACCOUNTS[:cash_bank],
      amount: payout.amount,
      type:   'payout_completed',
      desc:   "Payout ##{payout.id} completed to #{payout.vendor.business_name}",
      payout: payout
    )
  end

  # ── Payout rejected (reverse staging) ──
  def self.record_payout_rejected(payout)
    create_entry(
      debit:  ACCOUNTS[:payout_payable],
      credit: ACCOUNTS[:seller_receivable],
      amount: payout.amount,
      type:   'payout_rejected',
      desc:   "Payout ##{payout.id} rejected, funds returned to #{payout.vendor.business_name}",
      payout: payout
    )
  end

  # ── Tax withheld on payout ──
  def self.record_tax_withheld(payout)
    create_entry(
      debit:  ACCOUNTS[:payout_payable],
      credit: ACCOUNTS[:wht_payable],
      amount: payout.tax_withheld,
      type:   'tax_withheld',
      desc:   "WHT 2% on payout ##{payout.id} to #{payout.vendor.business_name}",
      payout: payout
    )
  end

  # ── Refund (full or partial) ──
  def self.record_refund(order, amount)
    if order.completed? || FinancialLedger.exists?(order: order, transaction_type: 'funds_release_seller')
      create_entry(
        debit:  ACCOUNTS[:refunds_receivable],
        credit: ACCOUNTS[:cash_bank],
        amount: amount,
        type:   'refund_clawback',
        desc:   "Refund clawback for Order ##{order.id}",
        order:  order
      )
    else
      create_entry(
        debit:  ACCOUNTS[:liability_uncleared],
        credit: ACCOUNTS[:cash_bank],
        amount: amount,
        type:   'refund',
        desc:   "Refund for Order ##{order.id}",
        order:  order
      )
    end
  end

  # ── Clawback seller commission when refund occurs ──
  def self.record_refund_clawback(order, amount)
    create_entry(
      debit:  ACCOUNTS[:refunds_receivable],
      credit: ACCOUNTS[:seller_receivable],
      amount: amount,
      type:   'refund_clawback',
      desc:   "Commission clawback for Order ##{order.id}",
      order:  order
    )
  end

  # ── Penalty charged to seller for return shipping ──
  def self.record_seller_shipping_penalty(order, amount)
    create_entry(
      debit:  ACCOUNTS[:refunds_receivable],
      credit: ACCOUNTS[:seller_receivable],
      amount: amount,
      type:   'seller_shipping_penalty',
      desc:   "Return shipping penalty for Order ##{order.id}",
      order:  order
    )
  end

  # ── COD remittance (logistics partner pays platform) ──
  def self.record_cod_remittance(order, amount)
    create_entry(
      debit:  ACCOUNTS[:cash_bank],
      credit: ACCOUNTS[:liability_uncleared],
      amount: amount,
      type:   'cod_remittance',
      desc:   "COD remittance for Order ##{order.id}",
      order:  order
    )
  end

  # ── Delivery partner payout ──
  # Accepts PartnerPayout or any object responding to amount and logistics_partner
  def self.record_delivery_payout(payout)
    partner_name = if payout.respond_to?(:logistics_partner) && payout.logistics_partner
                     payout.logistics_partner.name
                   elsif payout.respond_to?(:description)
                     payout.description
                   else
                     "Delivery Partner"
                   end

    create_entry(
      debit:  ACCOUNTS[:logistics_payable],
      credit: ACCOUNTS[:cash_bank],
      amount: payout.amount,
      type:   'delivery_payout',
      desc:   "Delivery payout ##{payout.id} to #{partner_name}",
      payout: payout
    )
  end

  private

  def self.create_entry(debit:, credit:, amount:, type:, desc:, order: nil, vendor: nil, payout: nil)
    raise ArgumentError, "Amount must be positive, got #{amount}" unless amount.to_f > 0

    FinancialLedger.create!(
      transaction_type: type,
      debit_account:    debit,
      credit_account:   credit,
      amount:           amount,
      description:      desc,
      ledgerable:       order || vendor || payout
    )
  end
end