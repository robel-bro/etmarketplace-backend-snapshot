class SendSmsJob < ApplicationJob
  queue_as :default

  retry_on AfroMessageService::Error, wait: 5.seconds, attempts: 3

  def perform(phone:, message:)
    AfroMessageService.send_sms(phone: phone, message: message)
  end
end