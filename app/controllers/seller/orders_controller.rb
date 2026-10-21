# app/controllers/seller/orders_controller.rb

class Seller::OrdersController < Seller::BaseController
  before_action :ensure_vendor
  before_action :set_order, only: [:show, :accept, :reject, :update_status]

  rescue_from AASM::InvalidTransition, with: :render_invalid_transition
  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid

  # GET /seller/orders
  # Now supports server-side filtering: search, status, pagination
  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i.clamp(1, 100)

    base_scope = Order.where(vendor: current_user.vendor)
                      .includes(:user, :vendor, :checkout_group,
                                line_items: [:product, :package],
                                delivery_requests: :logistics_partner)

    # Apply search filter
    if params[:search].present?
      search_term = "%#{params[:search].downcase}%"
      base_scope = base_scope.joins(:user)
                             .left_joins(line_items: [:product, :package])
                             .where(
                               "orders.id::text ILIKE :term OR users.full_name ILIKE :term OR orders.shipping_address ILIKE :term OR products.title ILIKE :term OR packages.name ILIKE :term",
                               term: search_term
                             )
                             .distinct
    end

    # Apply status filter
    if params[:status].present? && params[:status] != 'all'
      base_scope = base_scope.where(status: params[:status])
    end

    total = base_scope.count
    orders = base_scope.order(created_at: :desc)
                       .limit(per_page)
                       .offset((page - 1) * per_page)

    render json: {
      data: orders.map { |o| order_json(o) },
      meta: {
        current_page: page,
        per_page: per_page,
        total_count: total,
        next_page: (page * per_page) < total ? page + 1 : nil,
        prev_page: page > 1 ? page - 1 : nil
      }
    }
  end

  # GET /seller/orders/:id
  def show
    authorize @order
    render json: order_json(@order)
  end

  # POST /seller/orders/:id/accept
  def accept
    if @order.status == 'accepted'
      return render json: { message: "Order already accepted.", order: order_json(@order) }
    end

    authorize @order

    # ★ FIX: Legacy pending COD orders need to transition to pending_acceptance first.
    if @order.status == 'pending' && @order.payment_cash_on_delivery? && @order.payment_status == 'pending'
      begin
        @order.pay! # transitions from pending to pending_acceptance for COD
      rescue AASM::InvalidTransition => e
        return render json: { error: "Order is not ready for acceptance: #{e.message}" }, status: :unprocessable_entity
      end
    end

    unless ['pending_acceptance', 'paid'].include?(@order.status)
      return render json: { error: "Order cannot be accepted in its current state." }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      unless @order.accept!
        raise ActiveRecord::Rollback, "Failed to accept order. Deadline may have passed."
      end

      group = @order.checkout_group
      if group
        group_orders = Order.where(checkout_group_id: group.id).lock
        if group_orders.all? { |o| o.status == 'accepted' }
          create_consolidated_delivery_request(group)
          group.update!(status: :dispatched) if group.respond_to?(:status)
        end
      end

      NotificationService.notify(@order.user, :order_accepted, { order_id: @order.id })
      NotificationService.notify(@order.vendor.user, :order_accepted_seller, {
        order_id: @order.id,
        status: 'accepted'
      })

      broadcast_seller_order(@order, 'order_updated')

      if group && group_orders.all? { |o| o.status == 'accepted' }
        ActionCable.server.broadcast("admin_deliveries", {
          type: 'delivery_request_created',
          checkout_group_id: group.id
        })
      end

      return render json: order_json(@order)
    end
  rescue ActiveRecord::Rollback => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "Accept failed for order #{@order.id}: #{e.class} - #{e.message}"
    render json: { error: 'Unable to accept order. Please try again.' }, status: :unprocessable_entity
  end

  # POST /seller/orders/:id/reject
  def reject
    if @order.status == 'cancelled'
      return render json: { message: "Order already cancelled.", order: order_json(@order) }
    end

    authorize @order

    # ★ FIX: Allow rejecting pending COD orders as well (but must transition first)
    if @order.status == 'pending' && @order.payment_cash_on_delivery? && @order.payment_status == 'pending'
      begin
        @order.pay!
      rescue AASM::InvalidTransition => e
        return render json: { error: "Order is not ready for rejection: #{e.message}" }, status: :unprocessable_entity
      end
    end

    unless ['pending_acceptance', 'paid'].include?(@order.status)
      return render json: { error: "Order cannot be rejected in its current state." }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      unless @order.reject!
        raise ActiveRecord::Rollback, "Failed to reject order. Deadline may have passed."
      end

      if @order.payment_completed?
        begin
          RefundService.new(@order).full_refund!
        rescue => e
          Rails.logger.error "Refund failed for rejected order #{@order.id}: #{e.message}"
        end
      end

      group = @order.checkout_group
      if group
        group_orders = Order.where(checkout_group_id: group.id).lock
        if group_orders.all? { |o| o.status == 'cancelled' }
          group.update!(status: :cancelled) if group.respond_to?(:status)
        else
          group.update!(status: :partial) if group.respond_to?(:status)
        end
      end

      NotificationService.notify(@order.user, :order_rejected_by_seller, { order_id: @order.id })

      broadcast_seller_order(@order, 'order_updated')
    end

    render json: order_json(@order)
  rescue ActiveRecord::Rollback => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "Reject failed for order #{@order.id}: #{e.class} - #{e.message}"
    render json: { error: 'Unable to reject order. Please try again.' }, status: :unprocessable_entity
  end

  # PATCH /seller/orders/:id/status
  def update_status
    authorize @order
    new_status = params[:status]
    case new_status
    when 'processing'
      return render_transition_error unless @order.may_process?
      @order.process!
    when 'shipped'
      return render_transition_error unless @order.may_ship?
      @order.ship!
      NotificationService.notify(@order.user, :shipment_created, {
        order_id: @order.id,
        carrier: @order.carrier_name || 'Delivery partner',
        tracking_number: @order.tracking_number || 'N/A'
      })
    else
      return render json: { error: "Invalid status" }, status: :unprocessable_entity
    end

    broadcast_seller_order(@order, 'order_updated')
    if new_status == 'shipped'
      ActionCable.server.broadcast("order_#{@order.id}", {
        type: 'shipment_created',
        order_id: @order.id,
        status: 'shipped'
      })
    end

    render json: order_json(@order)
  end

  private

  def set_order
    @order = Order.where(vendor: current_user.vendor)
                  .includes(:user, :vendor, :checkout_group,
                            line_items: [:product, :package],
                            delivery_requests: :logistics_partner)
                  .find(params[:id])
  end

  def ensure_vendor
    head :forbidden unless current_user.vendor.present?
  end

  def render_transition_error
    render json: { error: "Order cannot transition to that state" }, status: :unprocessable_entity
  end

  def render_invalid_transition(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  def render_record_invalid(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  # ─── Consolidated delivery request creation (updated) ─────────
  def create_consolidated_delivery_request(group)
    group_orders = Order.where(checkout_group_id: group.id).order(:id).to_a
    return if group_orders.empty?

    if DeliveryRequest.exists?(checkout_group_id: group.id, status: 'pending_assignment')
      return
    end

    total_weight_kg = 0.0
    total_volume_cm3 = 0.0
    refrigerated_needed = false
    fragile_needed = false

    group_orders.each do |order|
      order.line_items.each do |item|
        if item.product.present?
          product = item.product
          total_weight_kg += (product.weight_kg || 1.0) * item.quantity
          total_volume_cm3 += (product.length_cm.to_f * product.width_cm.to_f * product.height_cm.to_f) * item.quantity
          refrigerated_needed ||= product.product_attributes&.dig('refrigerated').to_s.downcase == 'true'
          fragile_needed ||= product.product_attributes&.dig('fragile').to_s.downcase == 'true'
        elsif item.package.present?
          package = item.package
          package.package_products.each do |pp|
            product = pp.product
            total_weight_kg += (product.weight_kg || 1.0) * item.quantity
            total_volume_cm3 += (product.length_cm.to_f * product.width_cm.to_f * product.height_cm.to_f) * item.quantity
            refrigerated_needed ||= product.product_attributes&.dig('refrigerated').to_s.downcase == 'true'
            fragile_needed ||= product.product_attributes&.dig('fragile').to_s.downcase == 'true'
          end
        end
      end
    end

    settings = Setting.get('logistics_defaults') || {}
    thresholds = settings['vehicle_weight_thresholds'] || {}
    motorcycle_max = thresholds['motorcycle_max_kg'].to_f || 20
    car_max = thresholds['car_max_kg'].to_f || 200
    van_max = thresholds['van_max_kg'].to_f || 1000

    required_type = if total_weight_kg <= motorcycle_max
                      'motorcycle'
                    elsif total_weight_kg <= car_max
                      'car'
                    elsif total_weight_kg <= van_max
                      'van'
                    else
                      'truck'
                    end

    first_order = group_orders.first
    pickup_points = group_orders.map do |order|
      vendor = order.vendor
      {
        vendor_id: vendor.id,
        vendor_name: vendor.business_name,
        lat: vendor.business_lat,
        lng: vendor.business_lng,
        address: vendor.business_address,
        phone: vendor.phone,
        package_weight: order.line_items.sum { |li| (li.product&.weight_kg || 0) * li.quantity },
        ready: true
      }
    end

    delivery_request = DeliveryRequest.create!(
      order: first_order,
      checkout_group_id: group.id,
      pickup_address: pickup_points.first[:address],
      delivery_address: first_order.shipping_address,
      pickup_contact_phone: pickup_points.first[:phone],
      delivery_contact_phone: first_order.user.phone,
      status: 'pending_assignment',
      pickup_points: pickup_points,
      consolidated_shipping_cost: group.consolidated_shipping_cost,
      total_subsidy: group.total_subsidy,
      buyer_shipping_cost: group.buyer_shipping_cost,
      required_vehicle_type: required_type,
      package_details: {
        weight_kg: total_weight_kg,
        volume_cm3: total_volume_cm3,
        refrigerated: refrigerated_needed,
        fragile: fragile_needed
      }
    )

    AssignmentService.broadcast_to_eligible_partners(delivery_request)

    ActionCable.server.broadcast("admin_deliveries", {
      type: 'delivery_request_created',
      delivery_request_id: delivery_request.id,
      checkout_group_id: group.id
    })
  rescue => e
    Rails.logger.error "Failed to create consolidated delivery request for group #{group.id}: #{e.class} - #{e.message}"
    raise
  end

  def broadcast_seller_order(order, event_type)
    ActionCable.server.broadcast("seller_orders_#{order.vendor_id}", {
      type: event_type,
      order_id: order.id,
      status: order.status,
      timestamp: Time.current.iso8601
    })
  end

  def order_json(order)
    group = order.checkout_group

    {
      id: order.id,
      buyer_name: order.user.full_name,
      total: order.total.to_f,
      shipping_cost: group&.consolidated_shipping_cost.to_f,
      consolidated_shipping: group&.buyer_shipping_cost.to_f,
      status: order.status,
      payment_status: order.payment_status,
      payment_method: order.payment_method_enum,
      created_at: order.created_at,
      acceptance_deadline: order.acceptance_deadline,
      delivery_pin: order.delivery_pin,
      pickup_pin: order.pickup_pin,
      vendor: {
        shop_name: order.vendor.business_name,
        business_address: order.vendor.business_address,
        phone: order.vendor.phone,
        business_lat: order.vendor.business_lat,
        business_lng: order.vendor.business_lng,
        accepting_orders: order.vendor.accepting_orders,
        reopen_at: order.vendor.reopen_at,
        pickup_ready: order.vendor.pickup_ready
      },
      items: order.line_items.map do |item|
        product = item.product
        package = item.package
        title = product&.title || package&.name || "Item ##{item.id}"
        image = product&.first_image_url
        image ||= package&.image_urls&.first if package && package.image_urls.is_a?(Array)

        {
          product_id: item.product_id,
          package_id: item.package_id,
          title: title,
          quantity: item.quantity,
          price: item.price.to_f,
          image: image,
          variant_attributes: item.variant_attributes.presence || {}
        }
      end,
      delivery_requests: order.delivery_requests.order(created_at: :desc).map do |dr|
        {
          id: dr.id,
          status: dr.status,
          vehicle_type: dr.vehicle_type,
          estimated_cost: dr.estimated_cost,
          pickup_address: dr.pickup_address,
          delivery_address: dr.delivery_address,
          accepted_at: dr.accepted_at,
          picked_up_at: dr.picked_up_at,
          delivered_at: dr.delivered_at,
          events: dr.events,
          logistics_partner: dr.logistics_partner ? { id: dr.logistics_partner.id, name: dr.logistics_partner.name } : nil,
          pickup_points: dr.pickup_points
        }
      end,
      return_request: order.return_requests.order(created_at: :desc).first&.then do |rr|
        {
          id: rr.id,
          status: rr.status,
          reason: rr.reason,
          details: rr.details,
          liability: rr.liability,
          return_shipping_cost: rr.return_shipping_cost,
          admin_notes: rr.admin_notes
        }
      end
    }
  end
end