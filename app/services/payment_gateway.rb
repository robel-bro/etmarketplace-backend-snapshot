module PaymentGateway
  # Factory method – picks the right gateway for an order
  def self.for(order)
    # Find matching active gateway from database
    config = PaymentGateway.active.find_by(provider: order.payment_method_enum)
    # Fallback to ENV if no config found (legacy)
    creds = config ? config.credentials : credentials_from_env(order.payment_method_enum)

    case order.payment_method_enum
    when 'telebirr'
      Telebirr.new(creds)
    when 'chapa'
      Chapa.new(creds)
    else
      NullGateway.new
    end
  end

  def self.credentials_from_env(provider)
    {
      api_key: ENV["#{provider.upcase}_API_KEY"],
      merchant_id: ENV["#{provider.upcase}_MERCHANT_ID"],
      webhook_secret: ENV["#{provider.upcase}_WEBHOOK_SECRET"]
    }.compact
  end

  class Telebirr
    def initialize(config)
      @api_key = config[:api_key]
      @merchant_id = config[:merchant_id]
      @webhook_secret = config[:webhook_secret]
      @config = config[:config] || {}
    end

    def charge(order, idempotency_key)
      { success: true, transaction_id: "TB_#{SecureRandom.hex(8)}" }
    end

    def refund(transaction_id, amount)
      { success: true, refund_id: "RF_#{SecureRandom.hex(8)}" }
    end

    def verify_webhook!(payload, signature_header)
      expected = OpenSSL::HMAC.hexdigest('SHA256', @webhook_secret.to_s, payload)
      unless ActiveSupport::SecurityUtils.secure_compare(expected, signature_header.to_s)
        raise "Invalid webhook signature"
      end
    end
  end

  class Chapa
    def initialize(config)
      @api_key = config[:api_key]
      @config = config[:config] || {}
    end

    def charge(order, idempotency_key)
      { success: true, transaction_id: "CH_#{SecureRandom.hex(8)}" }
    end

    def refund(transaction_id, amount)
      { success: true, refund_id: "RF_#{SecureRandom.hex(8)}" }
    end

    def verify_webhook!(payload, signature_header)
      # Chapa uses HMAC – implement similarly
    end
  end

  class NullGateway
    def charge(order, idempotency_key)
      { success: true, transaction_id: "NULL_#{SecureRandom.hex(8)}" }
    end

    def refund(transaction_id, amount)
      { success: true }
    end

    def verify_webhook!(payload, signature_header)
      true
    end
  end
end