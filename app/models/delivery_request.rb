# app/models/delivery_request.rb
class DeliveryRequest < ApplicationRecord
  attribute :cod_status, :integer, default: 0

  belongs_to :order
  belongs_to :logistics_partner, optional: true
  belongs_to :vehicle, optional: true
  belongs_to :driver, optional: true
  belongs_to :return_request, optional: true
  has_one :manual_dispatch, dependent: :destroy

  STATUSES = %w[
    pending_assignment assigned accepted confirmed_pickup picked_up in_transit
    delivered completed cancelled
  ].freeze

  VALID_TRANSITIONS = {
    'pending_assignment' => ['assigned', 'cancelled'],
    'assigned'           => ['accepted', 'cancelled'],
    'accepted'           => ['confirmed_pickup', 'picked_up', 'cancelled'],
    'confirmed_pickup'   => ['picked_up', 'cancelled'],
    'picked_up'          => ['in_transit', 'cancelled'],
    'in_transit'         => ['delivered', 'cancelled'],
    'delivered'          => ['completed'],
    'completed'          => [],
    'cancelled'          => []
  }.freeze

  validates :pickup_address, :delivery_address, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :status_transition_allowed, on: :update, if: :status_changed?

  before_validation :set_default_status, on: :create

  after_update :broadcast_status_change, if: :saved_change_to_status?
  after_update :auto_pay_partner, if: -> { saved_change_to_status? && status == 'completed' }
  after_update :sync_order_delivery, if: -> { saved_change_to_status? && status == 'completed' }
  after_update :complete_return_request, if: -> { saved_change_to_status? && status == 'completed' && return_delivery? }

  # ── Event logging ─────────────────────────────────────
  def add_event(status:, location: nil, note: nil)
    events_list = (events || [])
    events_list << {
      timestamp: Time.current.iso8601,
      status: status,
      location: location,
      note: note
    }
    update_columns(events: events_list)
    broadcast_event(events_list.last)
  end

  # ── Admin assigns a partner ───────────────────────────
  def assign_to_partner!(partner, vehicle = nil)
    raise "Request is not pending assignment" unless status == 'pending_assignment'
    if vehicle && vehicle.logistics_partner_id != partner.id
      raise ArgumentError, "Vehicle does not belong to partner"
    end
    if vehicle && !vehicle.available?
      raise ArgumentError, "Vehicle is not available"
    end

    with_lock do
      reload
      raise "Request already assigned" unless status == 'pending_assignment'

      update!(
        logistics_partner: partner,
        vehicle: vehicle,
        status: 'assigned',
        assigned_at: Time.current
      )
      vehicle&.update!(status: 'busy')
      add_event(status: 'assigned', note: "Assigned to #{partner.name}#{vehicle ? " (#{vehicle.plate_number})" : ''}")
    end
    true
  end

  # ── Partner accepts an assigned request ────────────────
  def accept_assignment!(partner, vehicle = nil, driver = nil)
    raise "Request is not assigned" unless status == 'assigned'

    vehicle ||= self.vehicle

    if vehicle && vehicle.logistics_partner_id != partner.id
      raise ArgumentError, "Vehicle does not belong to partner"
    end

    if driver && driver.logistics_partner_id != partner.id
      raise ArgumentError, "Driver does not belong to partner"
    end

    if driver && !driver.available?
      raise ArgumentError, "Driver is not available"
    end

    with_lock do
      reload
      raise "Request already accepted or cancelled" unless status == 'assigned'

      if logistics_partner && logistics_partner != partner
        raise "This request is assigned to another partner"
      end

      update!(
        logistics_partner: partner,
        vehicle: vehicle,
        driver: driver,
        status: 'accepted',
        accepted_at: Time.current
      )
      vehicle&.update!(status: 'busy')
      driver&.mark_on_delivery!
      add_event(status: 'accepted', note: "Accepted by #{partner.name} with driver #{driver&.name}")
    end
    true
  end

  # ── Seller confirms handover ──────────────────────────
  def confirm_pickup_by_seller!(location: nil)
    with_lock do
      reload
      raise "Cannot confirm pickup in #{status} status" unless status == 'accepted'
      change_status!('confirmed_pickup', pickup_confirmed_at: Time.current)
      add_event(status: 'confirmed_pickup', location: location, note: "Seller confirmed handover")
    end
    true
  end

  # ── Partner marks picked up ───────────────────────────
  def mark_picked_up!(location: nil)
    with_lock do
      reload
      raise "Cannot pick up in #{status}" unless %w[confirmed_pickup accepted].include?(status)
      change_status!('picked_up', picked_up_at: Time.current)
      add_event(status: 'picked_up', location: location)
    end
    true
  end

  # ── Partner marks in transit ──────────────────────────
  def mark_in_transit!(location: nil)
    with_lock do
      reload
      raise "Cannot start transit in #{status}" unless status == 'picked_up'
      change_status!('in_transit')
      add_event(status: 'in_transit', location: location)
    end
    true
  end

  # ── Partner marks delivered / collects COD ─────────────
  def mark_delivered!(location: nil, cod_collected: nil)
    with_lock do
      reload
      raise "Cannot deliver from #{status}" unless status == 'in_transit'
      attrs = { delivered_at: Time.current, status: 'delivered' }
      if order.payment_cash_on_delivery?
        attrs[:cod_status] = 2
      end
      change_status!('delivered', attrs)
      vehicle&.update!(status: 'available')
      driver&.mark_available!
      add_event(status: 'delivered', location: location, note: "COD collected: #{cod_collected}")
    end
    true
  end

  # ── Admin verifies COD ─────────────────────────────────
  def verify_cod!
    with_lock do
      reload
      raise "COD not applicable" unless order.payment_cash_on_delivery?
      raise "COD must be collected first" unless cod_status == 2
      update!(cod_status: 3)
      add_event(status: 'cod_verified', note: "COD verified by admin")
      complete!
    end
    true
  end

  # ── Complete request ──────────────────────────────────
  def complete!
    with_lock do
      reload
      raise "Cannot complete: current status #{status}" unless status == 'delivered'
      if order.payment_cash_on_delivery? && cod_status != 3
        raise "COD must be verified before completion"
      end
      change_status!('completed', completed_at: Time.current)
      vehicle&.update!(status: 'available')
      driver&.mark_available!
      add_event(status: 'completed')
    end
    true
  end

  # ── Cancel request ─────────────────────────────────────
  def cancel!(reason: nil)
    with_lock do
      reload
      raise "Cannot cancel from #{status}" if %w[completed cancelled].include?(status)
      change_status!('cancelled', cancelled_at: Time.current, cancel_reason: reason)
      vehicle&.update!(status: 'available')
      driver&.mark_available!
      add_event(status: 'cancelled', note: reason)
    end
    true
  end

  # ── Helper ────────────────────────────────────────────
  def return_delivery?
    return_request_id.present?
  end

  private

  def set_default_status
    self.status ||= 'pending_assignment'
  end

  def broadcast_new_request
    return if logistics_partner.present?

    partners = LogisticsPartner.active
                               .where(dispatch_mode: :internal_fleet, online: true)
                               .where("supported_vehicles @> ?", [required_vehicle_type].to_json)

    payload = {
      id: id,
      pickup_address: pickup_address,
      delivery_address: delivery_address,
      required_vehicle_type: required_vehicle_type,
      package_details: package_details,
      cod_amount: order.payment_cash_on_delivery? ? order.total : nil,
      estimated_earnings: nil,
      is_return: return_delivery?,
      return_reason: return_delivery? ? package_details&.dig('return_reason') : nil
    }

    partners.each do |partner|
      PartnerBoardChannel.broadcast_to(partner, {
        type: 'new_delivery_request',
        request: payload
      })
    end
  end

  def broadcast_status_change
    return unless status.present?
    OrderChannel.broadcast_to(order, {
      type: 'delivery_status_update',
      delivery_request_id: id,
      status: status,
      timestamp: Time.current.iso8601
    }) if defined?(OrderChannel)
  end

  def broadcast_event(event)
    OrderChannel.broadcast_to(order, {
      type: 'delivery_event',
      delivery_request_id: id,
      event: event
    }) if defined?(OrderChannel)
  end

  def status_transition_allowed
    return unless status_changed?
    allowed = VALID_TRANSITIONS[status_was] || []
    unless allowed.include?(status)
      errors.add(:status, "cannot transition from '#{status_was}' to '#{status}'")
    end
  end

  def change_status!(new_status, extra_attrs = {})
    raise "Invalid transition" unless VALID_TRANSITIONS[status]&.include?(new_status)
    update!(extra_attrs.merge(status: new_status))
  end

  def sync_order_delivery
    return unless order

    order.with_lock do
      order.update!(status: :delivered, delivered_at: Time.current)
      if order.payment_cash_on_delivery?
        order.update!(payment_status: :completed, paid_at: Time.current)
      end
    end
  rescue => e
    Rails.logger.error "Failed to sync order #{order.id} after delivery completion: #{e.message}"
  end

  def complete_return_request
    return unless return_request
    return_request.mark_received! if return_request.may?(:receive) || return_request.shipped_back?
  rescue => e
    Rails.logger.error "Failed to sync return request #{return_request&.id}: #{e.message}"
  end

  def auto_pay_partner
    return if order.payment_cash_on_delivery?
    return unless logistics_partner

    payout_amount = estimated_cost || consolidated_shipping_cost
    return if payout_amount.nil? || payout_amount <= 0

    return if PartnerPayout.exists?(delivery_request_id: id)

    ActiveRecord::Base.transaction do
      PartnerPayout.create!(
        logistics_partner: logistics_partner,
        delivery_request_id: id,
        amount: payout_amount,
        status: :paid,
        paid_at: Time.current,
        period_start: Date.today.beginning_of_month,
        period_end: Date.today.end_of_month
      )
      FinancialLedgerService.record_delivery_payout(id)
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[AutoPayout] Failed for DR #{id}: #{e.message}"
  end
end