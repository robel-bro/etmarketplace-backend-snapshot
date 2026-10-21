# app/services/assignment_service.rb
class AssignmentService
  # Create a DeliveryRequest for a newly placed order and broadcast to eligible partners.
  def self.create_delivery_request(order)
    analyzer = VehicleRequirementAnalyzer.new(order)

    vendor = order.vendor
    pickup_address = vendor.business_address.presence || vendor.business_name
    pickup_lat = vendor.business_lat
    pickup_lng = vendor.business_lng

    delivery_address = order.shipping_address
    delivery_lat = order.respond_to?(:delivery_lat) ? order.delivery_lat : nil
    delivery_lng = order.respond_to?(:delivery_lng) ? order.delivery_lng : nil

    dr = DeliveryRequest.new(
      order: order,
      pickup_address: pickup_address,
      pickup_lat: pickup_lat,
      pickup_lng: pickup_lng,
      delivery_address: delivery_address,
      delivery_lat: delivery_lat,
      delivery_lng: delivery_lng,
      package_details: {
        weight_kg: analyzer.actual_weight,
        volume_cm3: analyzer.volume,
        chargeable_weight_kg: analyzer.chargeable_weight,
        refrigerated: analyzer.refrigerated_needed,
        fragile: analyzer.fragile_needed
      },
      required_vehicle_type: analyzer.required_type,
      status: 'pending_assignment',
      service_level: order.respond_to?(:service_level) ? order.service_level : 0
    )

    # Set estimated_cost using the order's actual shipping cost.
    dr.estimated_cost = order.shipping_cost.to_f

    dr.save!

    # Broadcast to eligible partners (non‑fatal)
    begin
      broadcast_to_eligible_partners(dr)
    rescue => e
      Rails.logger.error "Broadcast failed for DR ##{dr.id}: #{e.message}"
    end

    dr
  end

  # Broadcast a new delivery request to all eligible partners.
  def self.broadcast_to_eligible_partners(delivery_request)
    analyzer = VehicleRequirementAnalyzer.new(delivery_request.order)
    partners = eligible_partners(analyzer)

    partners.each do |partner|
      payload = board_payload(partner, delivery_request)
      next unless payload

      begin
        # Use PartnerBoardChannel.broadcast_to so it matches stream_for in the channel
        PartnerBoardChannel.broadcast_to(partner, {
          type: 'new_delivery_request',
          request: payload
        })
        Rails.logger.info "Broadcast sent to partner #{partner.id} for DR ##{delivery_request.id}"
      rescue => e
        Rails.logger.error "Broadcast to partner #{partner.id} failed: #{e.message}"
      end
    end
  end

  # Build a consistent payload for a partner and a delivery request.
  def self.board_payload(partner, delivery_request)
    order = delivery_request.order
    return nil unless order

    # Include both product and package line items with variants
    products = order.line_items.includes(:product, package: { package_products: :product }).map do |li|
      if li.product.present?
        product = li.product
        variant_attrs = li.variant_attributes.presence
        variant = product.find_variant(variant_attrs) rescue nil
        {
          type: 'product',
          title: product.title || 'Unknown',
          quantity: li.quantity,
          weight_kg: variant&.weight_kg || product.weight_kg,
          price: variant&.price || product.price,
          image_url: product.images.attached? ?
                      Rails.application.routes.url_helpers.rails_blob_url(product.images.first) : nil,
          variant_attributes: variant_attrs || {}
        }
      elsif li.package.present?
        package = li.package
        package_items = package.package_products.map do |pp|
          product = pp.product
          next unless product
          {
            product_id: product.id,
            title: product.title,
            quantity: li.quantity,
            variant_attributes: pp.variant_attributes.presence || {}
          }
        end.compact
        {
          type: 'package',
          title: package.name || 'Package',
          quantity: li.quantity,
          weight_kg: package.package_products.sum { |pp| (pp.product&.weight_kg || 1.0) * li.quantity },
          price: package.current_price,
          image_url: package.image_urls.first,
          package_items: package_items
        }
      end
    end.compact

    # Calculate distance and this partner's estimated earnings
    distance = haversine(
      delivery_request.pickup_lat, delivery_request.pickup_lng,
      delivery_request.delivery_lat, delivery_request.delivery_lng
    ) || 10

    earnings = partner_estimate(partner, delivery_request, distance)

    {
      id: delivery_request.id,
      pickup_address: delivery_request.pickup_address,
      delivery_address: delivery_request.delivery_address,
      required_vehicle_type: delivery_request.required_vehicle_type,
      package_details: delivery_request.package_details || {},
      cod_amount: order.payment_cash_on_delivery? ? order.total : nil,
      payment_method: order.payment_method,
      products: products,
      estimated_earnings: earnings,
      service_level: delivery_request.service_level,
      delivery_label: delivery_label(delivery_request.service_level)
    }
  end

  # Return active, online partners with at least one suitable available vehicle.
  def self.eligible_partners(analyzer)
    query = LogisticsPartner.active
                            .online
                            .joins(:vehicles)
                            .where(vehicles: { status: :available })

    if analyzer.required_type.present?
      query = query.where(vehicles: { vehicle_type: analyzer.required_type })
    end
    # Note: We don't filter by weight/volume here because the partner may have multiple vehicles.
    # The can_accept flag will be used in the controller to determine final eligibility.
    query.distinct
  end

  # Estimate earnings for each partner using their own rate cards or admin defaults.
  def self.partner_estimate(partner, delivery_request, distance_km)
    weight_kg = delivery_request.package_details&.dig('chargeable_weight_kg') ||
                delivery_request.package_details&.dig('weight_kg').to_f
    volume_cm3 = delivery_request.package_details&.dig('volume_cm3').to_f
    vehicle_type = delivery_request.required_vehicle_type
    fragile = delivery_request.package_details&.dig('fragile') || false
    refrigerated = delivery_request.package_details&.dig('refrigerated') || false

    rate_card = partner.rate_cards.find_by(vehicle_type: vehicle_type)

    if rate_card
      base = rate_card.base_rate.to_f
      per_km = rate_card.per_km_rate.to_f
      min_charge = rate_card.min_charge.to_f
      weight_surcharge = rate_card.weight_surcharge_per_kg_above_5kg.to_f
      express_surcharge = rate_card.express_surcharge_percent.to_f
      fragile_surcharge = rate_card.fragile_surcharge.to_f
    else
      defaults = admin_defaults
      vehicle_default = defaults['default_base_rates']&.dig(vehicle_type) || {}
      base = vehicle_default['base']&.to_f || 50.0
      per_km = vehicle_default['per_km']&.to_f || 5.0
      min_charge = vehicle_default['min_charge']&.to_f || 50.0
      weight_surcharge = vehicle_default['weight_surcharge_per_kg']&.to_f || 2.0
      express_surcharge = defaults['express_surcharge_percent']&.to_f || 20.0
      fragile_surcharge = defaults['fragile_surcharge']&.to_f || 50.0
    end

    cost = base + (distance_km * per_km)

    # Weight surcharge (above base weight)
    base_weight = (admin_defaults['base_weight_kg'] || 5.0).to_f
    cost += (weight_kg - base_weight) * weight_surcharge if weight_kg > base_weight

    # Volume surcharge (if any)
    base_volume = (admin_defaults['base_volume_cm3'] || 10_000).to_f
    volume_surcharge_per_m3 = (admin_defaults.dig('default_base_rates', vehicle_type, 'volume_surcharge_per_m3') || 0).to_f
    if volume_cm3 > base_volume && volume_surcharge_per_m3 > 0
      extra_volume_m3 = (volume_cm3 - base_volume) / 1_000_000.0  # convert cm³ to m³
      cost += extra_volume_m3 * volume_surcharge_per_m3
    end

    # Express surcharge
    if delivery_request.service_level.to_i > 0
      cost += cost * (express_surcharge / 100.0)
    end

    # Fragile / refrigerated surcharges
    cost += fragile_surcharge if fragile
    cost += (admin_defaults['refrigerated_surcharge'] || 100).to_f if refrigerated

    cost = [cost, min_charge].max
    cost.round(2)
  end

  # Convert service_level integer to human-readable label.
  def self.delivery_label(service_level)
    case service_level.to_i
    when 0 then "Standard"
    when 1 then "Express"
    when 2 then "Next Day"
    else "Standard"
    end
  end

  # Haversine distance in km, returns nil if coordinates missing.
  def self.haversine(lat1, lng1, lat2, lng2)
    return nil if lat1.nil? || lng1.nil? || lat2.nil? || lng2.nil?

    r = 6371.0
    dlat = (lat2.to_f - lat1.to_f) * Math::PI / 180
    dlng = (lng2.to_f - lng1.to_f) * Math::PI / 180
    a = Math.sin(dlat / 2)**2 + Math.cos(lat1.to_f * Math::PI / 180) * Math.cos(lat2.to_f * Math::PI / 180) * Math.sin(dlng / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    (r * c).round(2)
  end

  private

  def self.admin_defaults
    @admin_defaults ||= begin
      stored = Setting.get('logistics_defaults') || {}
      VehicleRequirementAnalyzer::DEFAULTS.deep_merge(stored)
    end
  end
end