class Admin::MembershipPlansController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_plan, only: [:show, :update, :destroy]

  def index
    @plans = MembershipPlan.all
    render json: @plans
  end

  def show
    render json: @plan
  end

  def create
    @plan = MembershipPlan.new(plan_params)
    if @plan.save
      safe_audit('membership_plan_created', @plan, { name: @plan.name, price: @plan.price })
      render json: @plan, status: :created
    else
      render json: { errors: @plan.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    old_attrs = { name: @plan.name, price: @plan.price, commission_rate: @plan.commission_rate }
    if @plan.update(plan_params)
      new_attrs = { name: @plan.name, price: @plan.price, commission_rate: @plan.commission_rate }
      safe_audit('membership_plan_updated', @plan, { old: old_attrs, new: new_attrs })
      render json: @plan
    else
      render json: { errors: @plan.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    info = { id: @plan.id, name: @plan.name }
    @plan.destroy
    safe_audit('membership_plan_deleted', nil, info)
    head :no_content
  end

  private

  def set_plan
    @plan = MembershipPlan.find(params[:id])
  end

  def plan_params
    params.require(:membership_plan).permit(
      :name,
      :description,
      :price,
      :yearly_price,               # ★ NEW
      :duration_days,
      :commission_rate,
      :badge_text,
      :priority_support,
      :active,
      :featured_included,
      :featured_duration_days,
      :sponsored_product_limit,
      :analytics_access,
      features: []
    )
  end

  def safe_audit(action, record, details = {})
    AdminAuditLog.log(current_user, action, record, details)
  rescue NameError => e
    Rails.logger.warn "AdminAuditLog not available: #{e.message}"
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'membership_plans' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('membership_plans')
    head :forbidden
    false
  end
end