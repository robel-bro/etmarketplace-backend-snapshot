# app/controllers/admin/return_requests_controller.rb

class Admin::ReturnRequestsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_return_request, only: [:show, :update, :approve, :reject, :mark_received, :complete]

  # GET /admin/return_requests
  def index
    @return_requests = ReturnRequest.includes(
      :user,
      order: [:line_items, :vendor, { line_items: :product }]
    ).order(created_at: :desc)

    render json: @return_requests.map { |r| return_request_json(r) }
  end

  # GET /admin/return_requests/:id
  def show
    render json: return_request_json(@return_request)
  end

  # PATCH/PUT /admin/return_requests/:id
  # Note: status changes are handled by dedicated actions (approve, reject, etc.).
  # This generic update only allows editing admin_notes, liability, etc.
  def update
    if @return_request.update(return_request_params)
      AdminAuditLog.log(current_user, 'return_request_updated', @return_request)
      render json: return_request_json(@return_request)
    else
      render json: { errors: @return_request.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /admin/return_requests/:id/approve
  def approve
    ActiveRecord::Base.transaction do
      @return_request.approve!

      @return_request.update!(
        liability: params[:liability] || @return_request.liability,
        return_shipping_cost: params[:return_shipping_cost] || @return_request.return_shipping_cost,
        admin_notes: params[:admin_notes] || @return_request.admin_notes
      )

      # Notifications (safely rescued)
      begin
        NotificationService.notify(@return_request.user, "return_approved",
          return_id: @return_request.id,
          reason: @return_request.reason,
          details: @return_request.details
        )
      rescue => e
        Rails.logger.warn "Buyer notification failed: #{e.message}"
      end

      begin
        NotificationService.notify(@return_request.order.vendor.user, "return_approved_seller",
          return_id: @return_request.id,
          order_id: @return_request.order.id
        )
      rescue => e
        Rails.logger.warn "Seller notification failed: #{e.message}"
      end

      AdminAuditLog.log(current_user, 'return_request_approved', @return_request, { liability: @return_request.liability })
      render json: return_request_json(@return_request)
    end
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /admin/return_requests/:id/reject
  def reject
    @return_request.reject!(note: params[:admin_notes])

    begin
      NotificationService.notify(@return_request.user, "return_rejected",
        return_id: @return_request.id,
        reason: params[:admin_notes]
      )
    rescue => e
      Rails.logger.warn "Buyer notification failed: #{e.message}"
    end

    AdminAuditLog.log(current_user, 'return_request_rejected', @return_request, { admin_notes: params[:admin_notes] })
    render json: return_request_json(@return_request)
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /admin/return_requests/:id/mark_received
  # Idempotent: if already received, just render current state.
  def mark_received
    if @return_request.received?
      return render json: return_request_json(@return_request)
    end

    ActiveRecord::Base.transaction do
      @return_request.mark_received!
      @return_request.order.restore_stock

      begin
        NotificationService.notify(@return_request.order.vendor.user, "return_received",
          return_id: @return_request.id,
          order_id: @return_request.order.id
        )
      rescue => e
        Rails.logger.warn "Seller notification failed: #{e.message}"
      end

      AdminAuditLog.log(current_user, 'return_request_marked_received', @return_request)
      render json: return_request_json(@return_request)
    end
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /admin/return_requests/:id/complete
  # Only process refund & complete if return request has been received.
  def complete
    unless @return_request.received?
      return render json: { error: 'Return request must be received before completion' }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      begin
        RefundService.new(@return_request.order, return_request: @return_request).process!
      rescue => e
        Rails.logger.error "Refund failed for return #{@return_request.id}: #{e.message}"
        raise ActiveRecord::Rollback, e.message
      end

      @return_request.charge_return_shipping!
      @return_request.complete!

      begin
        NotificationService.notify(@return_request.user, "return_completed",
          return_id: @return_request.id,
          refund_amount: @return_request.order.refunded_amount
        )
      rescue => e
        Rails.logger.warn "Buyer notification failed: #{e.message}"
      end

      begin
        NotificationService.notify(@return_request.order.vendor.user, "return_completed_seller",
          return_id: @return_request.id,
          order_id: @return_request.order.id
        )
      rescue => e
        Rails.logger.warn "Seller notification failed: #{e.message}"
      end

      AdminAuditLog.log(current_user, 'return_request_completed', @return_request)
      render json: return_request_json(@return_request)
    end
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_return_request
    @return_request = ReturnRequest.find(params[:id])
  end

  # Accept both nested and flat params.
  # Removed :status – status changes must go through dedicated actions.
  def return_request_params
    if params[:return_request].present?
      params.require(:return_request).permit(:liability, :return_shipping_cost, :admin_notes, :return_tracking_number)
    else
      params.permit(:liability, :return_shipping_cost, :admin_notes, :return_tracking_number)
    end
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'disputes' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('disputes')
    render json: { error: 'Admin access required' }, status: :forbidden
    false
  end

  def return_request_json(return_request)
    order = return_request.order
    user = return_request.user
    vendor = order.vendor

    {
      id: return_request.id,
      order_id: return_request.order_id,
      status: return_request.status,
      reason: return_request.reason,
      details: return_request.details,
      created_at: return_request.created_at,
      admin_notes: return_request.admin_notes,
      liability: return_request.liability,
      return_shipping_cost: return_request.return_shipping_cost,
      return_tracking_number: return_request.return_tracking_number,
      user: {
        id: user.id,
        full_name: user.full_name,
        phone: user.phone,
        email: user.email
      },
      order: {
        id: order.id,
        total: order.total.to_f,
        status: order.status,
        vendor: {
          name: vendor&.business_name,
          phone: vendor&.phone,
          address: vendor&.business_address
        },
        return_window_days: order.return_window_days,
        restocking_fee_percent: order.restocking_fee_percent,
        return_shipping_responsibility: order.return_shipping_responsibility,
        items: order.line_items.map do |li|
          product = li.product
          {
            product_id: li.product_id,
            title: product&.title,
            quantity: li.quantity,
            price: li.price.to_f,
            image: product&.first_image_url
          }
        end
      }
    }
  end
end