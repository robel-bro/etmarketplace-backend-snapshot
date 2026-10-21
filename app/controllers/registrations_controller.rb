# app/controllers/registrations_controller.rb
class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: [:create, :send_otp, :verify_otp]

  # POST /sign_up
  def create
    # Enforce location restriction for new buyers
    locations_setting = Setting.get('locations', {})
    allowed = locations_setting['available_locations']
    if allowed.present?
      regions = allowed.split(',').map(&:strip).map(&:downcase)
      buyer_region = params[:region].to_s.downcase

      unless buyer_region.present? && regions.any? { |r| buyer_region.include?(r) }
        return render json: {
          error: "We don't currently serve your area. We only operate in: #{allowed}"
        }, status: :unprocessable_entity
      end
    end

    user = User.new(registration_params)

    # Everyone starts as a buyer – seller role is only granted after admin approval
    user.role_mask = User::ROLES['buyer']

    if user.save
      # Record consent for all published legal pages
      LegalPage.published.each do |page|
        user.record_consent!(page.key, page.version)
      end

      if Rails.env.development?
        user.update!(phone_verified: true)
      else
        OtpService.send_otp(user.phone)
      end

      render json: { message: "Account created. Please verify your phone.", user_id: user.id }, status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /send_otp
  def send_otp
    phone = params[:phone]
    unless phone.present? && phone.match?(/\A\+251[97]\d{8}\z/)
      render json: { error: "Valid Ethiopian phone number required" }, status: :unprocessable_entity
      return
    end

    if OtpService.send_otp(phone)
      render json: { message: "OTP sent" }
    else
      render json: { error: "Unable to send OTP. Try again later." }, status: :too_many_requests
    end
  end

  # POST /verify_otp
  def verify_otp
    phone = params[:phone]
    code  = params[:code]

    # ★ Rate limit: max 5 failed attempts per phone per 10 minutes
    failed_attempts = OtpLog.where(phone: phone)
                            .where(success: false)          # only failed verifications
                            .where('created_at > ?', 10.minutes.ago)
                            .count
    if failed_attempts >= 5
      return render json: { error: "Too many attempts. Please request a new code." }, status: :too_many_requests
    end

    user = User.find_by(phone: phone)
    if user && OtpService.verify_otp(phone, code)
      # Log successful verification
      OtpLog.create!(phone: phone, success: true)

      # Hardened token generation
      access_token  = JsonWebToken.encode_access(user)
      refresh_token = JsonWebToken.encode_refresh(user)
      user.update!(
        refresh_token_digest: Digest::SHA256.hexdigest(refresh_token),
        last_sign_in_at: Time.current     # marks first login → new_user? returns false afterwards
      )

      render json: {
        message:       "Phone verified",
        user:          user_data(user),
        access_token:  access_token,
        refresh_token: refresh_token
      }
    else
      # Log failed attempt
      OtpLog.create!(phone: phone, success: false)
      render json: { error: "Invalid or expired OTP" }, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:phone, :full_name, :password, :password_confirmation, :region)
  end

  def user_data(user)
    {
      id:             user.id,
      phone:          user.phone,
      full_name:      user.full_name,
      phone_verified: user.phone_verified,
      roles:          user.roles,
      new_user:       user.new_user?      # first login flag
    }
  end
end