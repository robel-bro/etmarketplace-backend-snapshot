class PaymentGatewayConfig < ApplicationRecord
  validates :name, :provider, presence: true
  validates :provider, uniqueness: true

  scope :active, -> { where(active: true) }

  # Credentials hash for the adapter
  def credentials
    {
      api_key: api_key,
      merchant_id: merchant_id,
      webhook_secret: webhook_secret,
      config: config
    }.compact
  end
end