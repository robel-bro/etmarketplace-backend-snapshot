require 'net/http'
require 'uri'
require 'json'
require 'securerandom'
require 'openssl'
require 'base64'

module Gateway
  class Telebirr
    attr_reader :config

    def initialize(gateway_record)
      @gateway_record = gateway_record
      @config = gateway_record.telebirr_credentials
    end

    def process(order)
      # Prevent duplicate payments – use a deterministic order ID based on the order's idempotency key
      merchant_order_id = "ORDER#{order.id}#{order.idempotency_key&.last(8) || SecureRandom.alphanumeric(8).upcase}"

      token = apply_fabric_token
      return { success: false, error: 'Unable to obtain fabric token' } unless token

      preorder_result = request_create_order(token, order, merchant_order_id)
      if preorder_result.nil? || preorder_result['result'] != 'SUCCESS'
        error_msg = preorder_result&.dig('msg') || 'Failed to create Telebirr order'
        Rails.logger.error "Telebirr preorder failed: #{error_msg} (full response: #{preorder_result.inspect})"
        return { success: false, error: error_msg }
      end

      prepay_id = preorder_result.dig('biz_content', 'prepay_id')
      unless prepay_id
        Rails.logger.error "Telebirr response missing prepay_id: #{preorder_result.inspect}"
        return { success: false, error: 'Invalid Telebirr response' }
      end

      checkout_url = generate_checkout_url(prepay_id)

      { success: true, checkout_url: checkout_url, prepay_id: prepay_id, merchant_order_id: merchant_order_id }
    rescue => e
      Rails.logger.error "Telebirr process error: #{e.message}"
      { success: false, error: 'Payment service temporarily unavailable' }
    end

    def self.verify_notification(payload, gateway_record)
      # Do NOT mutate the original payload
      sign_to_verify = payload['sign'] || payload[:sign]
      return false unless sign_to_verify

      # Build the string to sign from a copy of the payload without the sign field
      data = payload.dup
      data.delete('sign')
      data.delete(:sign)

      string_to_sign = build_sign_string(data)
      public_key = OpenSSL::PKey::RSA.new(gateway_record.public_key)
      public_key.verify_pss(
        OpenSSL::Digest::SHA256.new,
        Base64.decode64(sign_to_verify),
        string_to_sign,
        salt_length: :digest,
        mgf1_hash: 'SHA256'
      )
    rescue => e
      Rails.logger.error "Telebirr webhook verification error: #{e.message}"
      false
    end

    private

    def apply_fabric_token
      url = URI("#{config[:base_url]}/payment/v1/token")
      request = Net::HTTP::Post.new(url.path, {
        'Content-Type' => 'application/json',
        'X-APP-Key'    => config[:fabric_app_id]
      })
      request.body = { appSecret: config[:fabric_app_secret] }.to_json

      response = http_request(url, request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      body['token']
    rescue => e
      Rails.logger.error "applyFabricToken error: #{e.message}"
      nil
    end

    def request_create_order(token, order, merchant_order_id)
      url = URI("#{config[:base_url]}/payment/v1/merchant/preOrder")

      biz = {
        notify_url:         config[:notify_url],
        redirect_url:       config[:redirect_url],
        appid:              config[:merchant_app_id],
        merch_code:         config[:merchant_code],
        merch_order_id:     merchant_order_id,
        trade_type:         'Checkout',
        title:              "Order #{order.id}",
        total_amount:       order.total.to_f.to_s,
        trans_currency:     'ETB',
        timeout_express:    '120m',
        business_type:      'BuyGoods',
        payee_identifier:   config[:merchant_code],
        payee_identifier_type: '04',
        payee_type:         '5000',
        callback_info:      order.id.to_s   # Use order ID directly for webhook matching
      }

      req_body = {
        timestamp:  Time.current.to_i.to_s,
        nonce_str:  SecureRandom.hex(16).upcase,
        method:     'payment.preorder',
        version:    '1.0',
        biz_content: biz
      }

      req_body[:sign] = sign_request(req_body)
      req_body[:sign_type] = 'SHA256WithRSA'

      http_req = Net::HTTP::Post.new(url.path, {
        'Content-Type'  => 'application/json',
        'X-APP-Key'     => config[:fabric_app_id],
        'Authorization' => token
      })
      http_req.body = req_body.to_json

      response = http_request(url, http_req)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error "Telebirr preOrder HTTP error: #{response.code} #{response.body}"
        return nil
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      Rails.logger.error "Telebirr preOrder parse error: #{e.message}, body: #{response&.body}"
      nil
    rescue => e
      Rails.logger.error "requestCreateOrder error: #{e.message}"
      nil
    end

    def generate_checkout_url(prepay_id)
      raw_params = {
        appid:      config[:merchant_app_id],
        merch_code: config[:merchant_code],
        nonce_str:  SecureRandom.hex(16).upcase,
        prepay_id:  prepay_id,
        timestamp:  Time.current.to_i.to_s
      }

      sign = sign_request(raw_params)
      raw_request = [
        "appid=#{raw_params[:appid]}",
        "merch_code=#{raw_params[:merch_code]}",
        "nonce_str=#{raw_params[:nonce_str]}",
        "prepay_id=#{raw_params[:prepay_id]}",
        "timestamp=#{raw_params[:timestamp]}",
        "sign=#{sign}",
        "sign_type=SHA256WithRSA"
      ].join('&')

      web_base = config[:web_base_url] || 'https://developerportal.ethiotelebirr.et:38443/payment/web/paygate?'
      other_params = '&version=1.0&trade_type=Checkout'
      "#{web_base}#{raw_request}#{other_params}"
    end

    def sign_request(params)
      string_to_sign = self.class.build_sign_string(params)
      private_key = OpenSSL::PKey::RSA.new(config[:private_key])
      signature = private_key.sign_pss(
        OpenSSL::Digest::SHA256.new,
        string_to_sign,
        salt_length: 32,
        mgf1_hash: 'SHA256'
      )
      Base64.strict_encode64(signature)
    end

    def self.build_sign_string(params)
      exclude_fields = %w[sign sign_type header refund_info openType raw_request]
      fields = {}
      params.each do |key, value|
        next if exclude_fields.include?(key.to_s)
        if key.to_s == 'biz_content' && value.is_a?(Hash)
          value.each { |biz_key, biz_val| fields[biz_key.to_s] = biz_val }
        else
          fields[key.to_s] = value
        end
      end
      sorted_keys = fields.keys.sort
      sorted_keys.map { |k| "#{k}=#{fields[k]}" }.join('&')
    end

    def http_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      # ★ CRITICAL: Verify peer certificate in production
      if Rails.env.production? || ENV['FORCE_SSL_VERIFY'] == 'true'
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      http.read_timeout = 15
      http.open_timeout = 5
      http.request(request)
    end
  end
end