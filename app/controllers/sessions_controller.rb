# app/controllers/sessions_controller.rb

class SessionsController < ApplicationController
  allow_unauthenticated_access only: [:create, :refresh, :destroy]

  # POST /login
  def create
    email    = params[:email]&.strip&.downcase
    phone    = params[:phone]&.strip
    password = params[:password]

    if email.blank? && phone.blank?
      return render json: { error: "Email or phone and password required" }, status: :unprocessable_entity
    end

    unless password.present?
      return render json: { error: "Password required" }, status: :unprocessable_entity
    end

    # Determine lookup field: prefer email if provided, otherwise phone
    user = if email.present?
             User.find_by(email: email)
           else
             User.find_by(phone: phone)
           end

    return render json: { error: "Invalid credentials" }, status: :unauthorized unless user

    # Clear expired lock before checking locked status
    user.clear_expired_lock!

    if user.locked?
      return render json: { error: "Account temporarily locked" }, status: :too_many_requests
    end

    unless user.active_for_authentication?
      return render json: { error: "Account is not active" }, status: :forbidden
    end

    if user.authenticate(password)
      user.reset_failed_attempts!

      access_token  = JsonWebToken.encode_access(user)
      refresh_token = JsonWebToken.encode_refresh(user)
      user.update!(refresh_token_digest: Digest::SHA256.hexdigest(refresh_token))

      set_refresh_cookie(refresh_token)

      return render json: {
        user:          user_data(user),
        access_token:  access_token,
        refresh_token: refresh_token   # present for mobile
      }
    else
      user.record_failed_attempt!
      return render json: { error: "Invalid credentials" }, status: :unauthorized
    end
  rescue => e
    Rails.logger.error "Login error: #{e.message}"
    render json: { error: "An unexpected error occurred. Please try again." }, status: :internal_server_error
  end

  # POST /refresh – sliding expiration with token rotation
  def refresh
    token = cookies.encrypted[:refresh_token].presence || params[:refresh_token]
    return render json: { error: "No refresh token" }, status: :unauthorized unless token

    decoded = JsonWebToken.decode_refresh(token)
    return render json: { error: "Invalid refresh token" }, status: :unauthorized unless decoded.is_a?(Hash)

    user = User.find_by(id: decoded[:user_id])
    return render json: { error: "Invalid token" }, status: :unauthorized unless user

    expected_digest = Digest::SHA256.hexdigest(token)
    unless user.refresh_token_digest == expected_digest
      user.update!(refresh_token_digest: nil)
      cookies.delete(:refresh_token)
      return render json: { error: "Token reuse detected" }, status: :unauthorized
    end

    # Ensure account is still active / not locked before issuing new tokens
    unless user.active_for_authentication?
      user.update!(refresh_token_digest: nil)
      cookies.delete(:refresh_token)
      return render json: { error: "Account is no longer active" }, status: :forbidden
    end

    new_access  = JsonWebToken.encode_access(user)
    new_refresh = JsonWebToken.encode_refresh(user)
    user.update!(refresh_token_digest: Digest::SHA256.hexdigest(new_refresh))

    set_refresh_cookie(new_refresh)

    render json: {
      access_token:  new_access,
      refresh_token: new_refresh
    }
  rescue => e
    Rails.logger.error "Token refresh error: #{e.message}"
    render json: { error: "Unable to refresh session. Please login again." }, status: :unauthorized
  end

  # DELETE /logout
  def destroy
    if current_user
      # ✅ Clear refresh token AND FCM token
      current_user.update!(refresh_token_digest: nil, fcm_token: nil)
    end
    cookies.delete(:refresh_token)
    head :no_content
  rescue => e
    Rails.logger.error "Logout error: #{e.message}"
    head :no_content
  end

  # GET /session
  def show
    if current_user
      render json: { user: user_data(current_user) }
    else
      render json: { user: nil }
    end
  end

  # DELETE /account – user-initiated account deletion (soft delete)
  def destroy_account
    user = current_user
    return render json: { error: "Authentication required" }, status: :unauthorized unless user

    password = params[:password]
    if password.blank? || !user.authenticate(password)
      return render json: { error: "Password confirmation failed" }, status: :unauthorized
    end

    if user.deactivate_account!
      cookies.delete(:refresh_token)
      render json: { message: "Account deactivated successfully" }
    else
      render json: { error: "Unable to deactivate account" }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error "Account deletion error: #{e.message}"
    render json: { error: "Unable to process request" }, status: :internal_server_error
  end

  private

  # Include vendor/partner info and permissions for sub-admins
  def user_data(user)
    data = {
      id:             user.id,
      phone:          user.phone,
      email:          user.email,
      full_name:      user.full_name,
      phone_verified: user.phone_verified,
      roles:          user.roles,
      permissions:    user.permissions || [],   # ★ ADD THIS – frontend uses this to filter sidebar
      new_user:       user.new_user?,
      status:         user.status
    }

    if user.vendor.present?
      data[:vendor] = {
        id:            user.vendor.id,
        business_name: user.vendor.business_name,
        status:        user.vendor.status,
        approved:      user.vendor.status == 'approved'
      }
    end

    if user.logistics_partner
      data[:logistics_partner] = {
        id:     user.logistics_partner.id,
        name:   user.logistics_partner.name,
        status: user.logistics_partner.status,
        online: user.logistics_partner.online
      }
    end

    data
  end

  def set_refresh_cookie(token)
    cookies.encrypted[:refresh_token] = {
      value: token,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :strict,
      max_age: 7.days.to_i
    }
  end
end