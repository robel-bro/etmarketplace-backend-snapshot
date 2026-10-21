class Admin::ReturnPoliciesController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_policy, only: [:show, :update, :destroy]

  # GET /admin/return_policies
  def index
    @policies = ReturnPolicy.order(created_at: :desc)
    render json: @policies
  end

  # GET /admin/return_policies/:id
  def show
    render json: @policy
  end

  # POST /admin/return_policies
  def create
    policy = ReturnPolicy.new(policy_params)
    if policy.save
      render json: policy, status: :created
    else
      render json: { errors: policy.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /admin/return_policies/:id
  def update
    if @policy.update(policy_params)
      render json: @policy
    else
      render json: { errors: @policy.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /admin/return_policies/:id
  def destroy
    @policy.destroy
    head :no_content
  end

  private

  def set_policy
    @policy = ReturnPolicy.find(params[:id])
  end

  def policy_params
    params.permit(
      :name,
      :description,
      :return_window_days,
      :restocking_fee_percent,
      :return_shipping_responsibility,
      :is_active,
      applicable_categories: [],
      excluded_categories: []
    )
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'return_policies' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('return_policies')
    head :forbidden
    false
  end
end