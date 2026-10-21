class Admin::CouponsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_coupon, only: [:update, :destroy]

  def index
    @coupons = Coupon.all.order(created_at: :desc)
    render json: @coupons
  end

  def create
    @coupon = Coupon.new(coupon_params)
    if @coupon.save
      AdminAuditLog.log(current_user, 'coupon_created', @coupon, { code: @coupon.code, discount_value: @coupon.discount_value })
      render json: @coupon, status: :created
    else
      render json: { errors: @coupon.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    old_attrs = { code: @coupon.code, discount_value: @coupon.discount_value }
    if @coupon.update(coupon_params)
      new_attrs = { code: @coupon.code, discount_value: @coupon.discount_value }
      AdminAuditLog.log(current_user, 'coupon_updated', @coupon, { old: old_attrs, new: new_attrs })
      render json: @coupon
    else
      render json: { errors: @coupon.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    info = { id: @coupon.id, code: @coupon.code }
    @coupon.destroy
    AdminAuditLog.log(current_user, 'coupon_deleted', nil, info)
    head :no_content
  end

  private

  def set_coupon
    @coupon = Coupon.find(params[:id])
  end

  def coupon_params
    params.require(:coupon).permit(
      :code, :discount_type, :discount_value, :min_order_amount,
      :start_date, :end_date, :usage_limit, :per_user_limit, :active
    )
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'promo_codes' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('promo_codes')
    head :forbidden
    false
  end
end