# app/controllers/admin/base_controller.rb
module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin!
    before_action :set_admin_time_zone
    after_action :log_admin_action, unless: -> { request.get? || request.head? }

    # ── Permission map for sub-admin access ──────────────────────────
    # Controller_name => permission string(s)
    # A sub-admin with any of these permissions can access the controller.
    # Main admins always have access.
    CONTROLLER_PERMISSION_MAP = {
      'dashboard'              => 'dashboard',
      'users'                  => 'users',
      'vendors'                => 'sellers',
      'products'               => 'products',
      'packages'               => 'packages',
      'orders'                 => 'orders',
      'categories'             => 'categories',
      'announcements'          => 'announcements',
      'coupons'                => 'promo_codes',
      'logistics_partners'     => 'logistics',
      'cod_collection'         => 'cod_collection',
      'manual_dispatches'      => 'manual_dispatches',
      'payment_gateway_configs'=> 'payment_gateways',
      'partner_payouts'        => ['partner_payouts', 'payouts'],   # "payouts" also grants access
      'payouts'                => 'payouts',
      'financial_ledgers'      => 'financial_ledger',
      'return_requests'        => 'disputes',                       # return requests often part of disputes
      'return_policies'        => 'return_policies',
      'legal_pages'            => 'legal_pages',
      'collections'            => 'collections',
      'disputes'               => 'disputes',
      'reports'                => 'reports',
      'membership_plans'       => 'membership_plans',
      'settings'               => 'settings',
      # sub_admins_controller intentionally not included: only main admin
      # hero_banners, promotional_sections, product_attributes, etc. remain main admin only
    }.freeze

    private

    def authenticate_admin!
      unless current_user&.admin? || sub_admin_permitted?
        respond_to do |format|
          format.html { redirect_to root_path, alert: 'Access denied.' }
          format.json { render json: { error: 'Forbidden' }, status: :forbidden }
        end
      end
    end

    # Define a compatibility method for controllers that use `require_admin!`
    # This overrides the one from Authentication concern.
    def require_admin!
      return if current_user_active? && (current_user.admin? || sub_admin_permitted?)
      render json: { error: "Admin access required" }, status: :forbidden
    end

    # Check if the current user is a sub-admin with permission for this controller
    def sub_admin_permitted?
      return false unless current_user_active? && current_user.sub_admin?

      required_permissions = CONTROLLER_PERMISSION_MAP[controller_name]
      return false if required_permissions.blank?

      permissions = current_user.permissions || []
      Array(required_permissions).any? { |perm| permissions.include?(perm) }
    end

    def set_admin_time_zone
      Time.zone = current_user&.time_zone || 'Addis Ababa'
    end

    # ─── Audit logging ──────────────────────────────────
    def log_admin_action
      return unless current_user

      AdminAuditLog.create!(
        admin_user_id: current_user.id,
        action: "#{controller_name}##{action_name}",
        details: {
          params: params.except(:controller, :action, :format, :authenticity_token).to_unsafe_h,
          ip: request.remote_ip,
          user_agent: request.user_agent
        }
      )
    rescue => e
      Rails.logger.error "[AdminAuditLog] Failed to create log: #{e.message}"
    end

    # ─── Common error handlers ──────────────────────────
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity_error
    rescue_from ActionController::ParameterMissing, with: :bad_request

    def not_found
      respond_to do |format|
        format.html { render file: Rails.public_path.join('404.html'), status: :not_found, layout: false }
        format.json { render json: { error: 'Not found' }, status: :not_found }
      end
    end

    def unprocessable_entity_error(exception)
      respond_to do |format|
        format.html { redirect_back fallback_location: admin_dashboard_path, alert: exception.message }
        format.json { render json: { errors: exception.record.errors.full_messages }, status: :unprocessable_entity }
      end
    end

    def bad_request(exception)
      respond_to do |format|
        format.json { render json: { error: exception.message }, status: :bad_request }
      end
    end
  end
end