# app/controllers/admin/delivery_requests_controller.rb

class Admin::DeliveryRequestsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  # GET /admin/delivery_requests
  def index
    @requests = DeliveryRequest.includes(:logistics_partner, :vehicle,
                                          order: [:user, :vendor, line_items: :product])
                               .order(created_at: :desc)

    if params[:status].present?
      @requests = @requests.where(status: params[:status])
    end

    if params[:partner_id].present?
      @requests = @requests.where(logistics_partner_id: params[:partner_id])
    end

    if params[:search].present?
      search = "%#{params[:search]}%"
      @requests = @requests.joins(:order).where(
        'orders.id::text LIKE ? OR delivery_requests.pickup_address ILIKE ? OR delivery_requests.delivery_address ILIKE ?',
        search, search, search
      )
    end

    render json: @requests.map { |dr| delivery_request_json(dr) }
  end

  # GET /admin/delivery_requests/active
  def active
    @requests = DeliveryRequest.includes(:logistics_partner, :vehicle,
                                          order: [:user, :vendor, line_items: :product])
                               .where(status: ['picked_up', 'in_transit', 'delivered'])
                               .order(updated_at: :desc)

    render json: @requests.map { |dr| delivery_request_json(dr) }
  end

  # PATCH /admin/delivery_requests/:id/assign
  def assign
    dr = DeliveryRequest.find(params[:id])
    partner = LogisticsPartner.find(params[:partner_id])
    vehicle = partner.vehicles.find_by(id: params[:vehicle_id])

    unless dr.status == 'pending_assignment'
      return render json: { error: 'Request is not pending assignment' }, status: :unprocessable_entity
    end

    begin
      dr.assign_to_partner!(partner, vehicle)
      AdminAuditLog.log(current_user, 'delivery_request_assigned', dr, { partner: partner.name, vehicle: vehicle&.plate_number })
      render json: { message: 'Assigned successfully', status: dr.status }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # PATCH /admin/delivery_requests/:id/cancel
  def cancel
    dr = DeliveryRequest.find(params[:id])
    begin
      dr.cancel!(params[:reason] || 'Cancelled by admin')
      AdminAuditLog.log(current_user, 'delivery_request_cancelled', dr, { reason: params[:reason] })
      render json: { message: 'Cancelled', status: dr.status }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # PATCH /admin/delivery_requests/:id/reassign
  def reassign
    dr = DeliveryRequest.find(params[:id])
    partner = LogisticsPartner.find(params[:partner_id])
    vehicle = partner.vehicles.find_by(id: params[:vehicle_id])

    unless %w[assigned accepted confirmed_pickup picked_up in_transit].include?(dr.status)
      return render json: { error: 'Cannot reassign a completed or cancelled delivery' }, status: :unprocessable_entity
    end

    # Validate vehicle belongs to partner and is available (if provided)
    if vehicle && vehicle.logistics_partner_id != partner.id
      return render json: { error: 'Vehicle does not belong to partner' }, status: :unprocessable_entity
    end
    if vehicle && !vehicle.available?
      return render json: { error: 'Vehicle is not available' }, status: :unprocessable_entity
    end

    begin
      ActiveRecord::Base.transaction do
        old_partner_id = dr.logistics_partner_id
        old_vehicle = dr.vehicle

        # Release old vehicle
        old_vehicle&.update!(status: 'available')

        # Assign new partner and vehicle
        dr.update!(
          logistics_partner: partner,
          vehicle: vehicle,
          status: 'assigned',
          assigned_at: Time.current
        )
        vehicle&.update!(status: 'busy')

        AdminAuditLog.log(current_user, 'delivery_request_reassigned', dr, {
          old_partner_id: old_partner_id,
          new_partner: partner.name,
          new_vehicle: vehicle&.plate_number
        })
      end
      render json: { message: 'Reassigned successfully', status: dr.status }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  private

  # ★ Allow main admin, or sub-admin with 'orders' OR 'manual_dispatches' permission
  def authorize_admin
    return true if current_user&.admin?

    if current_user&.sub_admin?
      return true if current_user.permissions.include?('orders')
      return true if current_user.permissions.include?('manual_dispatches')
    end

    head :forbidden
    false
  end

  # Unified JSON response for DeliveryRequest – safe package_details parsing
  def delivery_request_json(dr)
    order = dr.order
    return_reason = nil
    pd = dr.package_details

    if pd.is_a?(String)
      begin
        pd = JSON.parse(pd)
      rescue JSON::ParserError
        pd = nil
      end
    end
    return_reason = pd['return_reason'] if pd.is_a?(Hash)

    {
      id: dr.id,
      order_id: order.id,
      partner_name: dr.logistics_partner&.name || 'Unassigned',
      vehicle_type: dr.required_vehicle_type,
      vehicle_plate: dr.vehicle&.plate_number,
      status: dr.status,
      pickup_address: dr.pickup_address,
      delivery_address: dr.delivery_address,
      cod_amount: order.payment_cash_on_delivery? ? order.total : nil,
      payment_method: order.payment_method,
      created_at: dr.created_at,
      accepted_at: dr.accepted_at,
      picked_up_at: dr.picked_up_at,
      delivered_at: dr.delivered_at,
      buyer_name: order.user&.full_name,
      buyer_phone: order.user&.phone,
      seller_name: order.vendor&.business_name,
      seller_phone: order.vendor&.phone,
      products: order.line_items.map { |li| { title: li.product&.title || 'N/A', quantity: li.quantity } },
      estimated_earnings: dr.estimated_cost,
      return_request_id: dr.return_request_id,
      is_return: dr.return_request_id.present?,
      return_reason: return_reason
    }
  end
end