module Gateway
  class Dynamic
    attr_reader :config

    def initialize(payment_gateway_record)
      @gateway = payment_gateway_record
      @config  = payment_gateway_record.credentials.symbolize_keys
    end

    def charge(order, idempotency_key)
      uri = URI.parse(@config[:api_endpoint].to_s + '/charge')
      payload = {
        amount: order.total,
        phone: order.user.phone,
        reference: idempotency_key || "order_#{order.id}",
        api_key: @config[:api_key],
        merchant_id: @config[:merchant_id]
      }

      response = make_request(uri, payload)

      if response[:success]
        { success: true, transaction_id: response[:transaction_id] || "GW_#{SecureRandom.hex(6)}" }
      else
        { success: false, error: response[:error] || 'Gateway declined' }
      end
    rescue => e
      Rails.logger.error "Dynamic gateway charge error: #{e.message}"
      { success: false, error: 'Payment service temporarily unavailable' }
    end

    def refund(transaction_id, amount, idempotency_key)
      uri = URI.parse(@config[:api_endpoint].to_s + '/refund')
      payload = {
        transaction_id: transaction_id,
        amount: amount,
        reference: idempotency_key,
        api_key: @config[:api_key],
        merchant_id: @config[:merchant_id]
      }

      response = make_request(uri, payload)

      if response[:success]
        { success: true, transaction_id: response[:transaction_id] || "RF_#{SecureRandom.hex(6)}" }
      else
        { success: false, error: response[:error] || 'Refund failed' }
      end
    rescue => e
      Rails.logger.error "Dynamic gateway refund error: #{e.message}"
      { success: false, error: 'Refund service temporarily unavailable' }
    end

    private

    def make_request(uri, payload)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 15
      http.open_timeout = 5

      request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
      request.body = payload.to_json

      response = http.request(request)
      body = JSON.parse(response.body) rescue {}

      if response.code.to_i.between?(200, 299)
        { success: true, transaction_id: body['transaction_id'] || body['tx_id'] || body['id'] }
      else
        { success: false, error: body['message'] || body['error'] || "Gateway returned #{response.code}" }
      end
    end
  end
end