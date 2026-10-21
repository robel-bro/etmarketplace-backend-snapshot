# app/models/sms_log.rb
class SmsLog < ApplicationRecord
  validates :phone, presence: true
  validates :status, presence: true
end