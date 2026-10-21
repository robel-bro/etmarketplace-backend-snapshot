# app/models/return_request.rb

class ReturnRequest < ApplicationRecord
  belongs_to :user
  belongs_to :order
  has_one :vendor, through: :order
  has_one :reverse_delivery_request,
          class_name: 'DeliveryRequest',
          foreign_key: :return_request_id,
          dependent: :destroy

  enum :status, {
    pending: 0,
    approved: 1,
    rejected: 2,
    shipped_back: 3,
    received: 4,
    completed: 5
  }, default: :pending

  validates :reason, presence: true
  validates :return_shipping_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  after_initialize :set_default_status, if: :new_record?
  after_update :handle_status_change, if: :saved_change_to_status?

  # ── Status helpers ────────────────────────────────────
  def seller_liable?
    liability == 'seller' || liability == 'split'
  end

  def restock_item?
    true
  end

  # ── State transitions ────────────────────────────────
  def approve!
    raise "Cannot approve: current status is #{status}" unless pending?
    update!(status: :approved)
    true
  end

  def reject!(note: nil)
    raise "Cannot reject: current status is #{status}" unless pending?
    update!(status: :rejected, admin_notes: note.presence || admin_notes)
    true
  end

  # Called by partner when return pickup is done
  def mark_shipped_back!(tracking_number: nil)
    raise "Cannot mark shipped back: current status is #{status}" unless approved?
    update!(
      status: :shipped_back,
      return_tracking_number: tracking_number.presence || return_tracking_number
    )
  end

  # Called when seller receives the returned items
  def mark_received!
    raise "Cannot mark received: current status is #{status}" unless shipped_back?
    update!(status: :received, received_at: Time.current)
  end

  # Called after refund is processed
  def complete!
    raise "Cannot complete: current status is #{status}" unless received?
    update!(status: :completed)
  end

  # ── Reverse delivery creation ─────────────────────────
  # Creates a DeliveryRequest with swapped addresses (buyer → seller)
  # and broadcasts to eligible partners.
  def create_reverse_delivery_request!
    # Prevent duplicate reverse delivery for same return
    return if reverse_delivery_request.present?

    # Determine pickup (buyer) and dropoff (seller) addresses
    pickup_address = order.shipping_address
    delivery_address = vendor.business_address.presence || vendor.business_name

    # Use geocodes if available; otherwise leave nil
    pickup_lat = order.respond_to?(:delivery_lat) ? order.delivery_lat : nil
    pickup_lng = order.respond_to?(:delivery_lng) ? order.delivery_lng : nil
    delivery_lat = vendor.business_lat
    delivery_lng = vendor.business_lng

    # Build package details from returned items
    analyzer = VehicleRequirementAnalyzer.new(order)

    delivery_request = build_reverse_delivery(
      pickup_address: pickup_address,
      pickup_lat: pickup_lat,
      pickup_lng: pickup_lng,
      delivery_address: delivery_address,
      delivery_lat: delivery_lat,
      delivery_lng: delivery_lng,
      package_details: {
        weight_kg: analyzer.min_weight_capacity,
        volume_cm3: analyzer.total_volume,
        refrigerated: analyzer.refrigerated_needed,
        fragile: analyzer.fragile_needed,
        return_reason: reason,
        return_request_id: id
      },
      required_vehicle_type: analyzer.required_type
    )

    delivery_request.save!

    # Broadcast to eligible partners (non‑fatal)
    begin
      AssignmentService.broadcast_to_eligible_partners(delivery_request)
    rescue => e
      Rails.logger.error "Broadcast failed for reverse DR ##{delivery_request.id}: #{e.message}"
    end

    delivery_request
  rescue => e
    Rails.logger.error "[ReturnRequest] Failed to create reverse delivery for Return ##{id}: #{e.message}"
    nil
  end

  # Charge the return shipping cost to the liable party (seller or platform)
  def charge_return_shipping!
    cost = return_shipping_cost.to_f
    return unless cost > 0

    case liability
    when 'seller'
      begin
        order.vendor.payouts.create!(
          amount: -cost,
          status: :paid,
          payout_method: 'return_shipping'
        )
      rescue => e
        Rails.logger.error "[ReturnRequest] Failed to charge seller for return shipping: #{e.message}"
      end
    when 'platform'
      FinancialLedgerService.record_return_shipping_platform(self, cost) if defined?(FinancialLedgerService)
    end
  end

  private

  def set_default_status
    self.status ||= :pending
  end

  def handle_status_change
    case status
    when 'approved'
      # Create reverse delivery exactly once.
      create_reverse_delivery_request! unless reverse_delivery_request.present?
    when 'received'
      # Trigger refund logic could be added here, but better keep external
    when 'completed'
      # No-op
    end
  end

  # Build a DeliveryRequest with reversed pickup/dropoff.
  def build_reverse_delivery(attributes)
    DeliveryRequest.new(
      order: order,
      return_request_id: id,
      pickup_address: attributes[:pickup_address],
      pickup_lat: attributes[:pickup_lat],
      pickup_lng: attributes[:pickup_lng],
      delivery_address: attributes[:delivery_address],
      delivery_lat: attributes[:delivery_lat],
      delivery_lng: attributes[:delivery_lng],
      package_details: attributes[:package_details],
      required_vehicle_type: attributes[:required_vehicle_type],
      status: 'pending_assignment'
    )
  end
end