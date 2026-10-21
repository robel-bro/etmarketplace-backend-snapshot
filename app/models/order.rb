# app/models/order.rb
class Order < ApplicationRecord
  include AASM

  attr_accessor :auto_cancel_mode
  attr_accessor :skip_total_validation   # used when overriding total for grouped payment

  belongs_to :user
  belongs_to :vendor
  belongs_to :coupon, optional: true
  belongs_to :checkout_group, optional: true

  has_many :line_items, dependent: :destroy, autosave: true
  has_many :products, through: :line_items
  has_many :order_payouts
  has_many :payouts, through: :order_payouts
  has_many :delivery_requests, dependent: :destroy
  has_many :order_events, dependent: :destroy
  has_many :return_requests, dependent: :destroy

  enum :payment_status, { pending: 0, completed: 1, failed: 2, refunded: 3 }, prefix: :payment
  enum :payment_method_enum, { cash_on_delivery: 0, telebirr: 1, chapa: 2 }, prefix: :payment

  enum :status, {
    pending: 0,
    paid: 1,
    pending_acceptance: 2,
    accepted: 3,
    processing: 4,
    shipped: 5,
    delivered: 6,
    cancelled: 7,
    returned: 8,
    completed: 9
  }

  validates :shipping_address, presence: true
  validates :total, numericality: { greater_than_or_equal_to: 0 }
  validate :total_matches_line_items, on: :create, unless: :skip_total_validation

  validates :restocking_fee_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :return_shipping_responsibility, inclusion: { in: %w[buyer seller platform] }, allow_nil: true

  before_validation :calculate_total, on: :create
  after_create :set_acceptance_deadline

  before_create :generate_delivery_pin
  before_create :generate_pickup_pin
  before_create :generate_invoice_token

  # Move SMS to after_commit to avoid network calls inside transaction
  after_commit :send_delivery_pin_sms, on: :create
  after_commit :send_pickup_pin_sms, on: :create

  # ★ New: Broadcast to seller's real-time order channel after creation
  after_create_commit :broadcast_new_order_to_seller

  aasm column: :status, enum: true do
    state :pending, initial: true
    state :paid
    state :pending_acceptance
    state :accepted
    state :processing
    state :shipped
    state :delivered
    state :cancelled
    state :returned
    state :completed

    event :pay, after: :after_pay do
      transitions from: :pending, to: :paid, guard: :payment_method_requires_payment?
      transitions from: :pending, to: :pending_acceptance, guard: :cash_on_delivery?
    end

    # ★ Fixed: restore stock on payment failure
    event :fail_payment, after: :handle_payment_failure do
      transitions from: [:pending, :paid], to: :cancelled
    end

    event :accept, after: :record_acceptance, guard: :within_acceptance_window? do
      transitions from: [:pending_acceptance, :paid], to: :accepted
    end

    # ★ Fixed: restore stock on seller rejection
    event :reject, after: :handle_rejection, guard: :within_acceptance_window? do
      transitions from: [:pending_acceptance, :paid], to: :cancelled
    end

    event :process do
      transitions from: :accepted, to: :processing
    end

    event :ship, after: :record_shipment do
      transitions from: :processing, to: :shipped
    end

    event :deliver, after: :record_delivery do
      transitions from: :shipped, to: :delivered
    end

    event :complete do
      transitions from: :delivered, to: :completed, guard: :return_window_expired?
    end

    # ★ Fixed: restore stock on return
    event :return, after: :handle_return do
      transitions from: :delivered, to: :returned
    end

    event :cancel, after: :handle_cancellation do
      transitions from: [:pending, :paid, :pending_acceptance, :accepted, :processing], to: :cancelled
    end
  end

  # ─── Financial accessors ────────────────────────
  def seller_earnings
    self[:seller_earning] || (subtotal - (commission_amount || 0)).round(2)
  end

  def subtotal
    line_items.sum { |li| (li.price || 0) * li.quantity }
  end

  def shipping_cost
    self[:shipping_cost] || 0
  end

  def estimated_delivery
    return "Delivered" if delivered?
    if shipped_at.present?
      seller_hours = vendor&.average_processing_hours || 1
      partner_days = delivery_requests.where.not(logistics_partner_id: nil).first&.logistics_partner&.estimated_days || 3
      total_hours = seller_hours + (partner_days * 24)
      estimated = shipped_at + total_hours.hours
      return estimated > Time.current ? estimated.strftime('%B %d, %Y') : "Should have arrived by #{estimated.strftime('%B %d, %Y')}"
    end
    if accepted_at.present?
      partner_days = delivery_requests.where.not(logistics_partner_id: nil).first&.logistics_partner&.estimated_days
      if partner_days
        prep_hours = vendor&.average_processing_hours || 1
        estimated = accepted_at + prep_hours.hours + partner_days.days
        return estimated.strftime('%B %d, %Y')
      end
    end
    partner_days = delivery_requests.where.not(logistics_partner_id: nil).first&.logistics_partner&.estimated_days || 3
    prep_hours = vendor&.average_processing_hours || 1
    estimated = created_at + prep_hours.hours + partner_days.days
    estimated.strftime('%B %d, %Y')
  end

  def return_window_expired?
    delivered_at.present? && (Time.current - delivered_at) > (return_window_days || 7).days
  end

  def acceptance_deadline
    read_attribute(:acceptance_deadline) || (created_at + ENV.fetch('ORDER_ACCEPTANCE_DEADLINE_MINUTES', 60).to_i.minutes)
  end

  def pending_acceptance?
    status == 'pending_acceptance'
  end

  def within_acceptance_window?
    return true if auto_cancel_mode
    return false unless pending_acceptance? || status == 'paid'
    Time.current <= acceptance_deadline
  end

  # ─── Stock restoration for cancelled/rejected/returned orders (idempotent) ───
  def restore_stock
    # Prevent double restoration
    return if order_events.exists?(event_type: 'stock_restored')

    line_items.each do |li|
      if li.package_id.present?
        package = Package.find_by(id: li.package_id)
        next unless package
        package.restock!(li.quantity)

        # Decrement sold_count for component products
        package.package_products.each do |pp|
          Product.where(id: pp.product_id).update_all("sold_count = GREATEST(sold_count - #{li.quantity}, 0)")
        end
      elsif li.product_id.present?
        product = Product.find_by(id: li.product_id)
        next unless product
        variant_attrs = li.respond_to?(:variant_attributes) ? li.variant_attributes.presence : nil
        product.restock!(li.quantity, variant_attrs)

        # Decrement product sold_count
        Product.where(id: product.id).update_all("sold_count = GREATEST(sold_count - #{li.quantity}, 0)")
      end
    end

    # Destroy any reservations attached to this order (legacy)
    Reservation.where(order_id: id).destroy_all

    # Mark as restored to prevent duplicate execution
    order_events.create!(
      event_type: 'stock_restored',
      actor: nil,
      status_from: status,
      status_to: status
    )
  end

  def zero_financials!
    update_columns(
      total: 0.0,
      shipping_cost: 0.0,
      discount_amount: 0.0,
      commission_amount: 0.0,
      seller_earning: 0.0,
      service_fee: 0.0,
      vat_amount: 0.0
    )
    line_items.update_all(price: 0.0, commission_amount: 0.0)
  end

  private

  # ★ Broadcast real-time notification to seller's channel
  def broadcast_new_order_to_seller
    ActionCable.server.broadcast(
      "seller_orders_#{vendor_id}",
      {
        type: 'order_created',
        order_id: id,
        status: status,
        created_at: created_at.iso8601
      }
    )
  rescue => e
    Rails.logger.error "Failed to broadcast new order to seller #{vendor_id}: #{e.message}"
  end

  # ★ Ensure line item prices are available before total calculation.
  # Fallback to product/package current price if line item price is nil.
  def calculate_total
    sub = line_items.sum do |li|
      price = li.price
      if price.nil? || price.zero?
        price = li.product&.current_price || li.package&.current_price || 0
      end
      price * li.quantity
    end

    self.shipping_cost ||= 0
    self.discount_amount ||= 0
    self.service_fee ||= 0
    self.vat_amount ||= 0
    self.commission_amount ||= 0

    self.total = sub + shipping_cost + service_fee + vat_amount - discount_amount
    self.seller_earning = (sub - commission_amount).round(2)
  end

  def total_matches_line_items
    expected = subtotal + (shipping_cost || 0) + (service_fee || 0) + (vat_amount || 0) - (discount_amount || 0)
    if (total - expected).abs > 0.01
      errors.add(:total, "does not match line items + fees + shipping - discount")
    end
  end

  def set_acceptance_deadline
    deadline = ENV.fetch('ORDER_ACCEPTANCE_DEADLINE_MINUTES', 60).to_i.minutes.from_now
    update_column(:acceptance_deadline, deadline)
  end

  def generate_delivery_pin
    self.delivery_pin = SecureRandom.random_number(1000..9999).to_s
  end

  def generate_pickup_pin
    self.pickup_pin = SecureRandom.random_number(1000..9999).to_s
  end

  def generate_invoice_token
    self.invoice_token = SecureRandom.urlsafe_base64(32)
  end

  def send_delivery_pin_sms
    return unless user.phone.present?
    SmsService.send(
      user.phone,
      "Your ET Marketplace delivery PIN: #{delivery_pin}. Share this with your rider on delivery."
    )
  rescue => e
    Rails.logger.error "Failed to send delivery PIN SMS to #{user.phone}: #{e.message}"
  end

  def send_pickup_pin_sms
    seller_phone = vendor&.user&.phone
    return unless seller_phone.present? && pickup_pin.present?
    SmsService.send(
      seller_phone,
      "Your ET Marketplace pickup PIN: #{pickup_pin}. Share this with the rider at handover."
    )
  rescue => e
    Rails.logger.error "Failed to send pickup PIN SMS to #{seller_phone}: #{e.message}"
  end

  def payment_method_requires_payment?
    !payment_cash_on_delivery?
  end

  def cash_on_delivery?
    payment_cash_on_delivery?
  end

  def after_pay
    unless payment_cash_on_delivery?
      update(payment_status: :completed, paid_at: Time.current)
    end
  end

  def record_acceptance
    update(accepted_at: Time.current)
    log_event(:seller_accepted, vendor.user)
  end

  def record_shipment
    update(shipped_at: Time.current)
    log_event(:shipped, vendor.user)
  end

  def record_delivery
    update(delivered_at: Time.current)
    if payment_cash_on_delivery?
      update(payment_status: :completed)
    end
    log_event(:delivered, nil)
  end

  def handle_cancellation
    restore_stock

    if payment_completed?
      log_event(:cancelled_after_payment, vendor.user || user)
    else
      zero_financials!
      log_event(:cancelled_before_payment, vendor.user || user)
    end
  end

  def handle_payment_failure
    restore_stock
    zero_financials!
    log_event(:payment_failed, user)
  end

  def handle_rejection
    restore_stock
    zero_financials!
    log_event(:seller_rejected, vendor.user)
  end

  def handle_return
    restore_stock
    log_event(:returned, user)
  end

  def log_event(event_type, actor = nil)
    order_events.create!(
      event_type: event_type,
      actor: actor,
      status_from: aasm.from_state,
      status_to: aasm.to_state
    )
  rescue => e
    Rails.logger.error "Failed to log order event: #{e.message}"
  end
end