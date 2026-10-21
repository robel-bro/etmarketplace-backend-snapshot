# app/controllers/admin/sub_admins_controller.rb

class Admin::SubAdminsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_sub_admin, only: [:show, :update, :destroy]

  # GET /admin/sub_admins
  def index
    page = (params[:page] || 1).to_i
    page = 1 if page < 1
    per_page = (params[:per_page] || 20).to_i
    per_page = 20 if per_page < 1 || per_page > 100

    scope = User.where(role_mask: 8)

    # Search by name, email, or phone
    if params[:search].present?
      term = "%#{params[:search].downcase}%"
      scope = scope.where(
        'LOWER(full_name) LIKE :term OR LOWER(email) LIKE :term OR phone LIKE :term',
        term: term
      )
    end

    # Filter by status
    if params[:status].present? && User.statuses.key?(params[:status])
      scope = scope.where(status: params[:status])
    end

    total = scope.count
    sub_admins = scope.order(created_at: :desc)
                      .limit(per_page)
                      .offset((page - 1) * per_page)

    render json: {
      data: sub_admins.map { |u| sub_admin_json(u) },
      meta: {
        current_page: page,
        per_page: per_page,
        total_count: total,
        total_pages: (total.to_f / per_page).ceil
      }
    }
  end

  # GET /admin/sub_admins/:id
  def show
    render json: sub_admin_json(@sub_admin)
  end

  # POST /admin/sub_admins
  def create
    data = sub_admin_params
    user = User.new(
      full_name: data[:full_name],
      email: data[:email],
      phone: data[:phone].presence,   # optional, may be nil
      password: data[:password],
      role_mask: 8,
      permissions: data[:permissions] || [],
      status: 'active',
      phone_verified: true
    )

    if user.save
      AdminAuditLog.log(current_user, 'sub_admin_created', user, {
        full_name: user.full_name,
        email: user.email,
        permissions: user.permissions
      })
      render json: sub_admin_json(user), status: :created
    else
      Rails.logger.warn "Sub-admin creation failed: #{user.errors.full_messages.join(', ')}"
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /admin/sub_admins/:id
  def update
    data = sub_admin_params

    update_attrs = {
      full_name: data[:full_name],
      email: data[:email],
      phone: data[:phone].presence,
      permissions: data[:permissions] || []
    }

    update_attrs[:status] = data[:status] if data[:status].present?
    update_attrs[:password] = data[:password] if data[:password].present?

    if @sub_admin.update(update_attrs)
      AdminAuditLog.log(current_user, 'sub_admin_updated', @sub_admin, {
        email: @sub_admin.email,
        permissions: @sub_admin.permissions,
        status: @sub_admin.status
      })
      render json: sub_admin_json(@sub_admin)
    else
      Rails.logger.warn "Sub-admin update failed: #{@sub_admin.errors.full_messages.join(', ')}"
      render json: { errors: @sub_admin.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /admin/sub_admins/:id
  def destroy
    @sub_admin.update!(status: 'inactive', refresh_token_digest: nil)
    AdminAuditLog.log(current_user, 'sub_admin_deactivated', @sub_admin, {})
    head :no_content
  end

  private

  def set_sub_admin
    @sub_admin = User.where(role_mask: 8).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Sub-admin not found' }, status: :not_found
  end

  def sub_admin_params
    if params[:sub_admin].present?
      params.require(:sub_admin).permit(:full_name, :email, :phone, :password, :status, permissions: [])
    else
      params.permit(:full_name, :email, :phone, :password, :status, permissions: [])
    end
  end

  def sub_admin_json(user)
    {
      id: user.id,
      full_name: user.full_name,
      email: user.email,
      phone: user.phone,
      role_mask: user.role_mask,
      status: user.status,
      phone_verified: user.phone_verified,
      permissions: user.permissions || [],
      last_login_at: user.respond_to?(:last_login_at) ? user.last_login_at : nil,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  # ★ Sub-admins cannot manage other sub-admins; main admin only
  def authorize_admin
    unless current_user&.admin?
      head :forbidden
      return false
    end
    true
  end
end