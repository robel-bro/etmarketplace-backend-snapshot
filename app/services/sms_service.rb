# app/services/sms_service.rb
class SmsService
  class << self
    # Sends an SMS asynchronously via AfroMessage (default)
    # @param phone_number [String] recipient phone number (any format; will be normalized)
    # @param message [String] the SMS body
    # @return [Boolean] true if the background job was enqueued, false if phone invalid
    def send(phone_number, message)
      phone = normalize_phone(phone_number)

      # Validate Ethiopian phone number format
      unless phone.match?(/\A\+251[79]\d{8}\z/)
        Rails.logger.warn "[SMS] Invalid phone number: #{phone_number}"
        return false
      end

      SendSmsJob.perform_later(phone: phone, message: message)
      true
    end

    # Synchronous version – only use when you need immediate response (e.g. testing)
    # @return [Hash] AfroMessage response
    def send!(phone_number, message)
      phone = normalize_phone(phone_number)
      AfroMessageService.send_sms(phone: phone, message: message)
    end

    private

    # Normalizes any Ethiopian phone number to +251XXXXXXXXX format
    def normalize_phone(phone)
      phone = phone.gsub(/\D/, '')
      phone = "+#{phone}" unless phone.start_with?('+')
      # Convert 0-prefixed numbers (e.g., 0912...) to +251...
      if phone.start_with?('+0')
        phone = "+251#{phone[2..]}"
      elsif phone.start_with?('0')
        phone = "+251#{phone[1..]}"
      end
      phone
    end
  end
end