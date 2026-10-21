# app/services/afro_message_service.rb
require 'net/http'
require 'uri'
require 'json'

class AfroMessageService
  API_ENDPOINT = 'https://api.afromessage.com/api/send'.freeze
  MAX_RETRIES  = 2

  class Error < StandardError; end
  class DeliveryFailure < Error; end

  def self.send_sms(phone:, message:)
    new.send_sms(phone: phone, message: message)
  end

  def send_sms(phone:, message:)
    last_error = nil

    (MAX_RETRIES + 1).times do |attempt|
      response = make_request(phone, message)
      log_attempt(phone, message, response, attempt)

      if response['acknowledge'] == 'success'
        return response
      else
        last_error = DeliveryFailure.new(
          "AfroMessage delivery failed: #{response['response']&.dig('errors')&.join(', ') || response}"
        )
        break if permanent_failure?(response)
      end

      sleep 1 * attempt if attempt < MAX_RETRIES
    end

    raise last_error || Error.new('AfroMessage request failed after retries')
  rescue JSON::ParserError => e
    log_error(phone, message, "Invalid JSON response: #{e.message}")
    raise Error, "Invalid JSON response from AfroMessage"
  rescue StandardError => e
    log_error(phone, message, e.message)
    raise Error, "AfroMessage request failed: #{e.message}"
  end

  private

  def make_request(phone, message)
    uri  = URI.parse(API_ENDPOINT)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.path)
    request['Authorization'] = "Bearer #{token}"
    request['Content-Type']   = 'application/json'

    # ⚠️ sender and identifier are not sent until a valid sender name is approved on AfroMessage
    body = { to: phone, message: message }
    # Uncomment these lines once your sender is approved:
    # body[:sender] = sender if sender.present?
    # body[:from]   = identifier if identifier.present?

    Rails.logger.info "[AfroMessage] Request body: #{body.to_json}"

    request.body = body.to_json
    response = http.request(request)
    JSON.parse(response.body)
  rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "Request failed: #{e.message}"
  end

  def token
    ENV.fetch('AFROMESSAGE_TOKEN')
  end

  def sender
    ENV['AFROMESSAGE_SENDER'].presence
  end

  def identifier
    ENV['AFROMESSAGE_IDENTIFIER'].presence
  end

  def permanent_failure?(response)
    errors = response.dig('response', 'errors') || []
    errors.any? { |e| e.match?(/invalid sender|invalid identifier/i) }
  end

  def log_attempt(phone, message, response, attempt)
    SmsLog.create(
      phone:    phone,
      message:  message,
      status:   response['acknowledge'],
      response: response.to_json,
      attempt:  attempt
    )
  rescue StandardError => e
    Rails.logger.error("Failed to log SMS attempt: #{e.message}")
  end

  def log_error(phone, message, error)
    SmsLog.create(
      phone:    phone,
      message:  message,
      status:   'error',
      response: error
    )
  rescue StandardError => e
    Rails.logger.error("Failed to log SMS error: #{e.message}")
  end
end