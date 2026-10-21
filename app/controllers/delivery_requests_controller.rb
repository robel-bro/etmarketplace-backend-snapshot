class DeliveryRequestsController < ApplicationController
  # Authentication only for seller creation; partners use API key
  before_action :require_authentication, only: [:create]
  before_action :set_order, only: [:create, :index]
  before_action :authorize_seller, only: [:create]

  # POST /orders/:order_id/delivery_requests
  def create
    dr = @order.delivery_requests.build(request_params)

    # Guarantee non‑nil addresses even if vendor / buyer data is missing
    dr.pickup_address        = @order.vendor.business_address.presence || "Seller address not provided"
    dr.delivery_address      = @order.shipping_address.presence        || "Buyer address not provided"
    dr.pickup_contact_phone  = @order.vendor.user.phone.presence       || "Unknown"
    dr.delivery_contact_phone = @order.user.phone.presence             || "Unknown"

    if dr.save
      render json: delivery_request_json(dr), status: :created
    else
      render json: { errors: dr.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /orders/:order_id/delivery_requests
  def index
    render json: @order.delivery_requests.order(created_at: :desc).map { |dr| delivery_request_json(dr) }
  end

  # POST /delivery_requests/:id/accept
  def accept
    dr = DeliveryRequest.find(params[:id])
    partner = authenticate_partner!

    unless dr.status == 'pending'
      return render json: { error: "Request is no longer pending" }, status: :unprocessable_entity
    end

    dr.accept_by!(partner)

    NotificationService.notify(dr.order.vendor.user, "delivery_accepted", {
      order_id: dr.order.id, partner: partner.name
    })
    NotificationService.notify(dr.order.user, "delivery_accepted", {
      order_id: dr.order.id, partner: partner.name
    })
    render json: delivery_request_json(dr)
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PATCH /delivery_requests/:id/status
  def update_status
    dr = DeliveryRequest.find(params[:id])
    partner = authenticate_partner!

    unless dr.logistics_partner == partner
      return render json: { error: "Not authorized to update this request" }, status: :forbidden
    end

    new_status = params[:status]
    location = params[:location]
    note = params[:note]

    case new_status
    when 'picked_up'
      dr.mark_picked_up!(location: location)
    when 'in_transit'
      dr.mark_in_transit!(location: location)
    when 'delivered'
      dr.mark_delivered!(location: location)
    else
      return render json: { error: "Invalid status update" }, status: :unprocessable_entity
    end

    NotificationService.notify(dr.order.user, "shipment_updated", {
      order_id: dr.order.id,
      partner: partner.name,
      status: new_status,
      location: location
    })

    render json: delivery_request_json(dr)
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_order
    @order = Order.find(params[:order_id])
  end

  def authorize_seller
    head :forbidden unless current_user.vendor == @order.vendor
  end

  def request_params
    params.require(:delivery_request).permit(:vehicle_type, :package_details)
  end

  def authenticate_partner!
    api_key = request.headers['X-Api-Key']
    partner = LogisticsPartner.find_by(api_key: api_key)
    render json: { error: "Invalid API key" }, status: :unauthorized unless partner
    partner
  end

  def delivery_request_json(dr)
    {
      id: dr.id,
      order_id: dr.order_id,
      status: dr.status,
      vehicle_type: dr.vehicle_type,
      estimated_cost: dr.estimated_cost,
      package_details: dr.package_details,
      pickup_address: dr.pickup_address,
      delivery_address: dr.delivery_address,
      pickup_contact_phone: dr.pickup_contact_phone,
      delivery_contact_phone: dr.delivery_contact_phone,
      accepted_at: dr.accepted_at,
      picked_up_at: dr.picked_up_at,
      delivered_at: dr.delivered_at,
      events: dr.events,
      logistics_partner: dr.logistics_partner ? { id: dr.logistics_partner.id, name: dr.logistics_partner.name } : nil
    }
  end
end