# app/models/otp_log.rb
class OtpLog < ApplicationRecord
  validates :phone, presence: true
end