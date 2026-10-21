# app/controllers/admin/users_controller.rb

class Admin::UsersController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_user, only: [:update, :destroy]

  # GET /admin/users
  def index
    @users = User.order(created_at: :desc)
    render json: @users.map { |u| user_json(u) }
  end

  # PATCH/PUT /admin/users/:id
  def update
    old_attrs = {
      full_name: @user.full_name,
      phone: @user.phone,
      role_mask: @user.role_mask,
      status: @user.status
    }

    if @user.update(user_params)
      new_attrs = {
        full_name: @user.full_name,
        phone: @user.phone,
        role_mask: @user.role_mask,
        status: @user.status
      }
      AdminAuditLog.log(current_user, 'user_updated', @user, { old: old_attrs, new: new_attrs })
      render json: user_json(@user)
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /admin/users/:id
  def destroy
    user_info = { id: @user.id, phone: @user.phone, full_name: @user.full_name }

    ActiveRecord::Base.transaction do
      # Soft-delete by clearing refresh token before destroying
      @user.update!(refresh_token_digest: nil)
      @user.destroy!
    end

    AdminAuditLog.log(current_user, 'user_deleted', nil, user_info)
    head :no_content
  rescue ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::InvalidForeignKey => e
    render json: { error: 'User cannot be deleted because they have associated records.' }, status: :unprocessable_entity
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'User not found' }, status: :not_found
    return false
  end

  def user_params
    params.require(:user).permit(:full_name, :phone, :role_mask, :status)
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'users' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('users')
    head :forbidden
    false
  end

  def user_json(user)
    {
      id:             user.id,
      phone:          user.phone,
      full_name:      user.full_name,
      role_mask:      user.role_mask,
      roles:          user.roles,
      status:         user.status,
      phone_verified: user.phone_verified,
      created_at:     user.created_at
    }
  end
end