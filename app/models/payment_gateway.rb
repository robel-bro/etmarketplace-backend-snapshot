class PaymentGateway < ApplicationRecord
  validates :name, :provider, presence: true
  validates :provider, uniqueness: true

  scope :active, -> { where(active: true) }

  # Generic credentials (for dynamic adapter)
  def credentials
    {
      api_key: api_key,
      merchant_id: merchant_id,
      webhook_secret: webhook_secret,
      config: config
    }.compact
  end

  # Telebirr‑specific credentials, stored in a single JSON blob
  def telebirr_credentials
    {
      fabric_app_id:     credentials_json['fabric_app_id'],
      fabric_app_secret: credentials_json['fabric_app_secret'],
      merchant_app_id:   credentials_json['merchant_app_id'],
      merchant_code:     merchant_id,
      private_key:       credentials_json['private_key'],
      public_key:        credentials_json['public_key'],
      base_url:          api_endpoint.presence || ENV['TELEBIRR_BASE_URL'],
      notify_url:        webhook_secret.presence,
      redirect_url:      config&.dig('redirect_url'),
      web_base_url:      config&.dig('web_base_url')
    }
  end
end