# app/controllers/api/delivery_controller.rb

class Api::DeliveryController < ApplicationController
  skip_before_action :require_authentication, only: [:verify_pin]
  before_action :require_authentication, only: [:update_location]

  # POST /api/delivery/verify_pin
  def verify_pin
    order = Order.find_by(id: params[:order_id])
    return render json: { error: "Order not found" }, status: :not_found unless order

    unless order.delivery_pin.present?
      return render json: { error: "No delivery PIN has been generated for this order yet." }, status: :unprocessable_entity
    end

    if order.delivered?
      return render json: { already_delivered: true, message: "This order has already been delivered." }
    end

    unless order.delivery_pin == params[:pin].to_s.strip
      return render json: { error: "Invalid PIN. Please check and try again." }, status: :unprocessable_entity
    end

    unless order.shipped?
      return render json: { error: "Order cannot be delivered yet. Current status: #{order.status}" }, status: :unprocessable_entity
    end

    # Mark order as delivered
    if order.respond_to?(:deliver!)
      order.deliver!
    else
      order.update_columns(status: Order.statuses[:delivered], delivered_at: Time.current)
    end

    if order.payment_cash_on_delivery?
      order.update_columns(payment_status: Order.payment_statuses[:completed])
    end

    dr = order.delivery_requests.last
    dr&.mark_delivered! if dr&.status == 'in_transit'

    # Notify buyer
    NotificationService.notify(order.user, :order_delivered, order_id: order.id)

    # Notify seller
    if order.vendor&.user
      NotificationService.notify(order.vendor.user, :order_delivered_seller, order_id: order.id)
    end

    render json: { success: true, message: "Order delivered successfully! ✅" }
  end

  # POST /api/delivery/update_location
  def update_location
    partner = current_user.logistics_partner
    return head :forbidden unless partner

    order = Order.find_by(id: params[:order_id])
    return render json: { error: "Order not found" }, status: :not_found unless order

    delivery_request = partner.delivery_requests.find_by(order_id: order.id)
    unless delivery_request
      return render json: { error: "Delivery request not found or not assigned to you" }, status: :unprocessable_entity
    end

    # Update location
    if params[:lat].present? && params[:lng].present?
      delivery_request.update(current_lat: params[:lat], current_lng: params[:lng])
    end

    # Handle status transitions via model methods
    status = params[:status]
    if status.present?
      begin
        case status
        when 'accepted'
          # Partner accept assignment if it's assigned to them
          if delivery_request.status == 'assigned'
            delivery_request.accept_assignment!(partner)
          end
        when 'picked_up'
          if %w[accepted confirmed_pickup].include?(delivery_request.status)
            delivery_request.mark_picked_up!(location: "#{params[:lat]},#{params[:lng]}")
          end
        when 'in_transit'
          if delivery_request.status == 'picked_up'
            delivery_request.mark_in_transit!(location: "#{params[:lat]},#{params[:lng]}")
          end
        when 'delivered'
          if delivery_request.status == 'in_transit'
            delivery_request.mark_delivered!(location: "#{params[:lat]},#{params[:lng]}", cod_collected: params[:cod_collected])
          end
        end
      rescue => e
        return render json: { error: e.message }, status: :unprocessable_entity
      end
    end

    event = {
      event: 'location_update',
      lat: params[:lat],
      lng: params[:lng],
      status: status || delivery_request.status,
      at: Time.current.iso8601
    }
    delivery_request.events << event
    delivery_request.save(validate: false)

    DeliveryChannel.broadcast_to(order, {
      type: params[:lat].present? ? 'location_update' : 'status_update',
      lat: params[:lat],
      lng: params[:lng],
      status: delivery_request.status,
      estimated_delivery: order.try(:estimated_delivery),
      timestamp: Time.current.iso8601
    })

    render json: { success: true }
  end
end