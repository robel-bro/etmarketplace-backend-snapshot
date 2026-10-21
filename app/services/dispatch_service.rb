# app/services/dispatch_service.rb

class DispatchService
  # Dispatch to a SPECIFIC partner only.
  # This service is used for manual/API dispatch when an admin explicitly selects a partner.
  # It must NOT auto-assign to the first active partner.
  def self.broadcast(delivery_request, partner: nil)
    partner ||= delivery_request.logistics_partner

    unless partner&.active?
      return { status: 'error', error: 'No active logistics partner provided for dispatch' }
    end

    new(delivery_request, partner).call
  end

  def initialize(delivery_request, partner)
    @dr = delivery_request
    @order = @dr.order
    @group = CheckoutGroup.find_by(id: @order.checkout_group_id)
    @partner = partner
  end

  def call
    case @partner.dispatch_mode
    when 'manual'
      dispatch_manual
    when 'external_api'
      dispatch_api
    when 'internal_fleet'
      dispatch_internal
    else
      { status: 'error', error: "Unknown dispatch mode: #{@partner.dispatch_mode}" }
    end
  rescue => e
    Rails.logger.error "[DispatchService] Error for DR ##{@dr.id}: #{e.message}"
    @dr.events << { event: 'dispatch_error', error: e.message, at: Time.current.iso8601 }
    @dr.save(validate: false)
    { status: 'error', partner: @partner.name, error: e.message }
  end

  private

  # ─── Manual Dispatch ───────────────────────────────
  def dispatch_manual
    manual = ManualDispatch.create!(
      delivery_request: @dr,
      logistics_partner: @partner,
      admin_user: nil,
      status: :pending
    )

    manifest = @dr.pickup_points.presence || @group&.manifest || []

    manifest_url = begin
                     Rails.application.routes.url_helpers.manifest_url(@dr.id)
                   rescue
                     nil
                   end

    buyer_phone = @order.user&.phone

    begin
      NotificationService.notify_admin(
        :manual_dispatch_needed,
        {
          manual_dispatch_id: manual.id,
          delivery_request_id: @dr.id,
          partner_name: @partner.name,
          pickup_count: manifest.size,
          buyer_address: @dr.delivery_address,
          buyer_phone: buyer_phone,
          delivery_pin: @order.delivery_pin,
          manifest_url: manifest_url
        }
      )
    rescue NoMethodError => e
      Rails.logger.warn "[DispatchService] NotificationService.notify_admin missing: #{e.message}"
    end

    send_delivery_pin_sms(@order.user, @order)
    send_delivery_pin_sms(@order.vendor&.user, @order) if @order.vendor&.user

    @dr.update!(
      status: 'assigned',
      logistics_partner: @partner,
      assigned_at: Time.current,
      events: (@dr.events || []) + [{ event: 'assigned', partner: @partner.name, at: Time.current.iso8601 }]
    )
    { status: 'assigned', partner: @partner.name, manual_dispatch_id: manual.id }
  end

  # ─── External API Dispatch ─────────────────────────
  def dispatch_api
    payload = build_api_payload
    response = send_to_partner(payload)
    if response_success?(response)
      mark_assigned

      send_delivery_pin_sms(@order.user, @order)
      send_delivery_pin_sms(@order.vendor&.user, @order) if @order.vendor&.user

      { status: 'assigned', partner: @partner.name }
    else
      mark_failed(response)
      { status: 'failed', partner: @partner.name, error: response.body }
    end
  end

  def dispatch_internal
    # Internal fleet is managed through the open board, not direct dispatch.
    { status: 'error', error: 'Internal fleet dispatch not implemented yet' }
  end

  # ─── Build payload for API partners ────────────────
  def build_api_payload
    manifest = @dr.pickup_points.presence || @group&.manifest || []

    # Use order address for dropoff lat/lng if columns missing
    dropoff_lat = @dr.respond_to?(:delivery_lat) ? @dr.delivery_lat : @order.address&.latitude
    dropoff_lng = @dr.respond_to?(:delivery_lng) ? @dr.delivery_lng : @order.address&.longitude

    {
      pickups: manifest.map do |m|
        {
          vendor: m[:vendor_name],
          lat: m[:pickup_lat],
          lng: m[:pickup_lng],
          address: m[:pickup_address],
          contact_phone: m[:pickup_phone],
          ready: m[:ready],
          items: (m[:items] || []).map { |i| { name: i[:title], quantity: i[:quantity], image_url: i[:image_url] } }
        }
      end,
      dropoff: {
        lat: dropoff_lat,
        lng: dropoff_lng,
        address: @dr.delivery_address,
        contact_phone: @order.user&.phone,
        notes: @dr.package_details
      },
      order_ref: @order.id,
      delivery_pin: @order.delivery_pin,
      total_weight_kg: @group&.total_weight_kg
    }
  end

  def send_to_partner(payload)
    uri = URI(@partner.api_endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 10
    request = Net::HTTP::Post.new(uri.path.presence || '/')
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{@partner.api_key}"
    request.body = payload.to_json
    http.request(request)
  end

  def response_success?(response)
    response.is_a?(Net::HTTPSuccess) || response.code.to_i.between?(200, 299)
  end

  # Mark delivery request as assigned to partner
  def mark_assigned
    @dr.update!(
      status: 'assigned',
      logistics_partner: @partner,
      assigned_at: Time.current,
      events: (@dr.events || []) + [{ event: 'assigned', partner: @partner.name, at: Time.current.iso8601 }]
    )
  end

  def mark_failed(response)
    Rails.logger.error "[DispatchService] Partner #{@partner.name} responded with #{response.code}: #{response.body}"
    @dr.events << { event: 'dispatch_failed', partner: @partner.name, status_code: response.code.to_i, body: response.body, at: Time.current.iso8601 }
    @dr.save(validate: false)
  end

  # Helper: enqueue delivery PIN SMS to a user
  def send_delivery_pin_sms(user, order)
    return unless user&.phone.present? && order.delivery_pin.present?

    NotificationService.notify(
      user,
      :delivery_pin,
      order_id: order.id,
      delivery_pin: order.delivery_pin
    )
  end
end