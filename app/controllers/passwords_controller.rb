# app/controllers/passwords_controller.rb
class PasswordsController < ApplicationController
  allow_unauthenticated_access only: [:send_reset_code, :reset]

  # POST /passwords/send_reset_code
  def send_reset_code
    phone = params[:phone]&.strip
    unless phone.present? && phone.match?(/\A\+251[79]\d{8}\z/)
      return render json: { error: "Valid Ethiopian phone number required" }, status: :unprocessable_entity
    end

    user = User.find_by(phone: phone)
    # Always return the same message to prevent phone enumeration
    unless user
      return render json: { message: "If an account with that phone number exists, a reset code has been sent." }
    end

    # Rate limit: max 3 requests per 15 minutes per phone
    recent = OtpLog.where(phone: phone).where('created_at > ?', 15.minutes.ago).count
    if recent >= 3
      return render json: { error: "Too many requests. Please try again later." }, status: :too_many_requests
    end

    user.generate_otp!
    sms_sent = SmsService.send(phone, "Your ET Marketplace password reset code is: #{user.otp_code}")
    unless sms_sent
      return render json: { error: "Unable to send reset code. Please try again." }, status: :internal_server_error
    end

    OtpLog.create!(phone: phone)
    render json: { message: "If an account with that phone number exists, a reset code has been sent." }
  rescue => e
    Rails.logger.error "Password reset code send failed for #{phone}: #{e.message}"
    render json: { error: "Something went wrong. Please try again." }, status: :internal_server_error
  end

  # POST /passwords/reset
  def reset
    phone = params[:phone]&.strip
    code  = params[:code]&.strip
    new_password = params[:password]

    unless phone.present? && code.present? && new_password.present?
      return render json: { error: "Phone, code, and new password are required." }, status: :unprocessable_entity
    end

    # ★ Rate limit: max 5 failed reset attempts per phone per 15 minutes
    failed_attempts = OtpLog.where(phone: phone)
                            .where(success: false)
                            .where('created_at > ?', 15.minutes.ago)
                            .count
    if failed_attempts >= 5
      return render json: { error: "Too many attempts. Please request a new code." }, status: :too_many_requests
    end

    unless new_password.length >= 8
      return render json: { error: "Password must be at least 8 characters." }, status: :unprocessable_entity
    end

    # Same complexity check as User model
    unless new_password.match?(/\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[[:^alnum:]])/x)
      return render json: { error: "Password must include at least one uppercase letter, one lowercase letter, one number, and one special character." }, status: :unprocessable_entity
    end

    user = User.find_by(phone: phone)
    return render json: { error: "Invalid or expired code." }, status: :unprocessable_entity unless user

    unless user.verify_otp(code)
      # Log failed reset attempt
      OtpLog.create!(phone: phone, success: false)
      return render json: { error: "Invalid or expired code." }, status: :unprocessable_entity
    end

    user.update!(password: new_password)
    # Invalidate all existing sessions for security
    user.update!(refresh_token_digest: nil)

    render json: { message: "Password has been reset successfully. You can now sign in with your new password." }
  rescue => e
    Rails.logger.error "Password reset failed for #{phone}: #{e.message}"
    render json: { error: "Something went wrong. Please try again." }, status: :internal_server_error
  end
end