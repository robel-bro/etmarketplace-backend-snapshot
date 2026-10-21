# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization

  protect_from_forgery with: :exception, unless: -> { request.format.json? }

  before_action :require_authentication
  before_action :set_active_storage_url_options
  before_action :capture_request_info         # ★ capture IP / user-agent for audit
  before_action :enforce_admin_ip_whitelist   # ★ optional IP whitelist for admin area

  allow_browser versions: :modern

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from StandardError, with: :internal_server_error unless Rails.env.development?

  def self.admin_only!(options = {})
    before_action :require_admin!, **options
  end

  def self.seller_only!(options = {})
    before_action :require_seller!, **options
  end

  def self.buyer_only!(options = {})
    before_action :require_buyer!, **options
  end

  private

  def set_active_storage_url_options
    ActiveStorage::Current.url_options = {
      host: request.host,
      port: request.port
    }
  end

  # ── Store IP and User‑Agent for audit logs ──────────
  def capture_request_info
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
  end

  # ── Optional: restrict admin to whitelisted IPs ──────
  def enforce_admin_ip_whitelist
    return unless request.path.start_with?('/admin')

    allowed = ENV.fetch('ALLOWED_ADMIN_IPS', '').split(',').map(&:strip).reject(&:empty?)
    return if allowed.empty?   # whitelist disabled – allow all

    unless allowed.include?(request.remote_ip)
      Rails.logger.warn "Admin access blocked for IP: #{request.remote_ip}"
      render json: { error: 'Access denied. Your IP is not authorized for the admin area.' }, status: :forbidden
    end
  end

  def user_not_authorized
    render json: { error: "You are not authorized to perform this action." }, status: :forbidden
  end

  def internal_server_error(exception)
    Rails.logger.error "Internal Server Error: #{exception.class} - #{exception.message}\n#{exception.backtrace&.first(10)&.join("\n")}"
    render json: { error: "An unexpected error occurred. Our team has been notified." }, status: :internal_server_error
  end
end