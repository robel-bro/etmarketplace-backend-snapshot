# app/controllers/return_requests_controller.rb

class ReturnRequestsController < ApplicationController
  before_action :require_authentication
  before_action :set_return_request, only: [:show, :update, :approve, :reject]

  # GET /return_requests
  def index
    @requests = if current_user.admin?
                  ReturnRequest.includes(:order, :vendor, :user).all
                elsif current_user.seller? && current_user.vendor.present?
                  ReturnRequest.joins(:order)
                               .where(orders: { vendor_id: current_user.vendor.id })
                               .includes(:order, :vendor, :user)
                else
                  current_user.return_requests.includes(:order, :vendor, :user)
                end

    render json: @requests.map { |r| return_request_json(r) }
  end

  # GET /return_requests/:id
  def show
    return unless authorize_seller_or_admin(@request)
    render json: return_request_json(@request)
  end

  # POST /return_requests
  def create
    @request = current_user.return_requests.new(return_request_params)
    if @request.save
      render json: return_request_json(@request), status: :created
    else
      render json: { errors: @request.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /return_requests/:id
  def update
    return unless authorize_seller_or_admin(@request)

    attrs = return_request_update_params
    if attrs[:status].present?
      handle_status_change(attrs)
    else
      if @request.update(attrs)
        render json: return_request_json(@request)
      else
        render json: { errors: @request.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  # POST /return_requests/:id/approve
  def approve
    return unless authorize_seller_or_admin(@request)
    begin
      @request.approve!
      render json: { message: 'Return approved', return_request: return_request_json(@request) }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # POST /return_requests/:id/reject
  def reject
    return unless authorize_seller_or_admin(@request)
    note = params[:admin_notes] || params[:return_request]&.dig(:admin_notes)
    begin
      @request.reject!(note: note)
      render json: { message: 'Return rejected', return_request: return_request_json(@request) }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def set_return_request
    @request = ReturnRequest.find(params[:id])
  end

  def return_request_params
    if params[:return_request].present?
      params.require(:return_request).permit(:order_id, :reason, :details, :liability)
    else
      params.permit(:order_id, :reason, :details, :liability)
    end
  end

  def return_request_update_params
    if params[:return_request].present?
      params.require(:return_request).permit(:status, :admin_notes, :liability, :return_shipping_cost)
    else
      params.permit(:status, :admin_notes, :liability, :return_shipping_cost)
    end
  end

  def handle_status_change(attrs)
    status = attrs[:status].to_s
    if status == 'approved'
      @request.approve!
      @request.update_column(:admin_notes, attrs[:admin_notes]) if attrs[:admin_notes].present?
      render json: return_request_json(@request)
    elsif status == 'rejected'
      @request.reject!(note: attrs[:admin_notes])
      render json: return_request_json(@request)
    else
      if @request.update(attrs)
        render json: return_request_json(@request)
      else
        render json: { errors: @request.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  # ✅ Fixed: return true if authorized, false and render error if not.
  def authorize_seller_or_admin(request)
    return true if current_user.admin?
    if current_user.seller? && current_user.vendor.present?
      return true if request.order&.vendor_id == current_user.vendor.id
    end
    render json: { error: 'Forbidden' }, status: :forbidden
    false
  end

  def return_request_json(request)
    {
      id: request.id,
      order_id: request.order_id,
      user_id: request.user_id,
      status: request.status,
      reason: request.reason,
      details: request.details,
      liability: request.liability,
      admin_notes: request.admin_notes,
      return_shipping_cost: request.return_shipping_cost,
      created_at: request.created_at,
      updated_at: request.updated_at,
      vendor: request.vendor ? { id: request.vendor.id, name: request.vendor.business_name } : nil,
      order_total: request.order&.total
    }
  end
end