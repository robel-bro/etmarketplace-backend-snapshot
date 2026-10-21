class Admin::PaymentGatewayConfigsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_gateway, only: [:show, :update, :destroy]

  def index
    @gateways = PaymentGateway.all.order(:name)
    render json: @gateways
  end

  def show
    render json: @gateway
  end

  def create
    @gateway = PaymentGateway.new(gateway_params)
    if @gateway.save
      AdminAuditLog.log(current_user, 'payment_gateway_created', @gateway, { name: @gateway.name, provider: @gateway.provider })
      render json: @gateway, status: :created
    else
      render json: { errors: @gateway.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    old_attrs = { name: @gateway.name, provider: @gateway.provider, active: @gateway.active }
    if @gateway.update(gateway_params)
      new_attrs = { name: @gateway.name, provider: @gateway.provider, active: @gateway.active }
      AdminAuditLog.log(current_user, 'payment_gateway_updated', @gateway, { old: old_attrs, new: new_attrs })
      render json: @gateway
    else
      render json: { errors: @gateway.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    info = { id: @gateway.id, name: @gateway.name, provider: @gateway.provider }
    @gateway.destroy
    AdminAuditLog.log(current_user, 'payment_gateway_deleted', nil, info)
    head :no_content
  end

  private

  def set_gateway
    @gateway = PaymentGateway.find(params[:id])
  end

  def gateway_params
    params.require(:payment_gateway).permit(
      :name, :provider, :api_key, :merchant_id, :webhook_secret,
      :api_endpoint, :active, :supports_refunds,
      :private_key, :public_key,
      :fabric_app_id, :fabric_app_secret,
      :merchant_app_id,
      config: {}
    )
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'payment_gateways' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('payment_gateways')
    head :forbidden
    false
  end
end