# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :require_authentication

  # DELETE /account
  def destroy
    current_user.update!(status: :inactive)
    current_user.sessions.destroy_all

    render json: { message: "Account deactivated. We're sorry to see you go." }
  end

  # PATCH /users/welcome
  def welcome
    if current_user
      current_user.update!(welcomed_at: Time.current)
      render json: {
        user: {
          id:             current_user.id,
          phone:          current_user.phone,
          full_name:      current_user.full_name,
          phone_verified: current_user.phone_verified,
          roles:          current_user.roles,
          new_user:       current_user.new_user?   # now false
        }
      }
    else
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end
end