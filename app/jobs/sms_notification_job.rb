# app/jobs/sms_notification_job.rb

class SmsNotificationJob < ApplicationJob
  queue_as :default

  def perform(phone, message)
    # Send via existing SMS pipeline (AfroMessage, Telebirr, etc.)
    SmsService.send(phone, message)
  rescue => e
    Rails.logger.error "[SmsNotificationJob] Failed to send SMS to #{phone}: #{e.message}"
  end
end