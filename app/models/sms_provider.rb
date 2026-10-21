class SmsProvider < ApplicationRecord
  validates :name, :provider, presence: true
  validates :provider, uniqueness: true

  scope :active, -> { where(active: true) }

  # Credentials hash formatted for SmsService
  def credentials
    case provider
    when 'twilio'
      {
        api_key: api_key,
        auth_token: auth_token,   # add column if missing
        phone_number: phone_number
      }.compact
    when 'africas_talking'
      {
        api_key: api_key,
        username: username,       # add column if missing
        phone_number: phone_number
      }.compact
    else
      { api_key: api_key, phone_number: phone_number }.compact
    end
  end
end