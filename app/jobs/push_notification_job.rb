# app/jobs/push_notification_job.rb
require 'googleauth'
require 'net/http'
require 'uri'
require 'json'
require 'stringio'

class PushNotificationJob < ApplicationJob
  queue_as :default

  FCM_V1_URL = 'https://fcm.googleapis.com/v1/projects/et-marketplace-43806/messages:send'
  MAX_RETRIES = 3

  def perform(user_id, title, body, metadata = {}, priority = 'normal')
    user = User.find_by(id: user_id)
    return unless user&.fcm_token.present?

    payload = build_payload(user.fcm_token, title, body, metadata, priority)

    begin
      response = send_fcm_request(payload)

      if response.code.to_i == 200
        Rails.logger.info "[PushNotificationJob] Push sent successfully to user #{user.id}."
      else
        error_body = safe_parse_json(response.body)
        Rails.logger.error "[PushNotificationJob] Push failed: #{response.code} - #{error_body}"
        handle_error(response, error_body, user)
      end
    rescue => e
      Rails.logger.error "[PushNotificationJob] Error sending push to user #{user.id}: #{e.message}"
    end
  end

  private

  def build_payload(token, title, body, metadata, priority)
    android_config = {
      priority: priority.to_s.upcase,
      ttl: '86400s'
    }

    # Set notification channel/sound based on priority
    android_config[:notification] = if priority.to_s == 'high'
      {
        channel_id: 'order_alerts',
        sound: 'alarm.wav',
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      }
    else
      {
        channel_id: 'default_channel',
        sound: 'bell.wav',
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      }
    end

    # Convert metadata values to strings, but flatten if nested hashes/arrays are present
    data_payload = (metadata || {}).transform_values do |v|
      v.is_a?(Hash) || v.is_a?(Array) ? v.to_json : v.to_s
    end
    data_payload['priority'] = priority.to_s
    # ★ Add type if present for app routing
    data_payload['type'] = metadata[:type].to_s if metadata[:type].present?

    {
      message: {
        token: token,
        notification: {
          title: title,
          body: body
        },
        data: data_payload,
        android: android_config
      }
    }
  end

  def send_fcm_request(payload)
    uri = URI(FCM_V1_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.path, {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}"
    })
    request.body = payload.to_json

    http.request(request)
  end

  def access_token
    creds_file = Rails.root.join('config', 'firebase-service-account.json')
    creds_data = JSON.parse(File.read(creds_file))
    scope = 'https://www.googleapis.com/auth/firebase.messaging'
    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(creds_data.to_json),
      scope: scope
    )
    authorizer.fetch_access_token!['access_token']
  rescue => e
    Rails.logger.error "[PushNotificationJob] Failed to obtain access token: #{e.message}"
    raise
  end

  def handle_error(response, error_body, user)
    # If token is invalid/unregistered, clear it so we don't keep trying
    if response.code.to_i == 404 ||
       error_body&.dig('error', 'details')&.any? { |d| d['errorCode'] == 'UNREGISTERED' }
      user.update(fcm_token: nil)
      Rails.logger.info "[PushNotificationJob] Cleared invalid FCM token for user #{user.id}"
    end
  end

  def safe_parse_json(body)
    JSON.parse(body)
  rescue JSON::ParserError
    { "error" => "Invalid JSON response" }
  end
end