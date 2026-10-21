class OtpService
  MAX_OTP_PER_HOUR = 3

  # Send an OTP to the user with the given phone number
  def self.send_otp(phone)
    user = User.find_by(phone: phone)
    return false unless user

    # Rate limit: max 3 OTPs per hour per phone
    recent = OtpLog.where(phone: phone).where('created_at > ?', 1.hour.ago).count
    if recent >= MAX_OTP_PER_HOUR
      Rails.logger.info "OTP rate limit reached for #{phone}"
      return false
    end

    # Generate OTP on the user record
    user.generate_otp!

    # Send SMS via SmsService (now uses AfroMessage asynchronously)
    sms_sent = SmsService.send(phone, "Your ET Marketplace verification code is: #{user.otp_code}")
    unless sms_sent
      Rails.logger.error "OTP SMS failed to enqueue for #{phone}"
      return false
    end

    # Log the request for rate‑limiting
    OtpLog.create!(phone: phone)
    true
  rescue => e
    Rails.logger.error "OTP send failed for #{phone}: #{e.message}"
    false
  end

  # Verify the code for the given phone number
  def self.verify_otp(phone, code)
    user = User.find_by(phone: phone)
    return false unless user

    user.verify_otp(code)
  end
end