# app/controllers/concerns/authentication.rb

module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :current_vendor, :logged_in?, :authenticated?,
                  :admin?, :seller?, :buyer?, :sub_admin?, :current_user_active?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  # ---------- Guards ----------
  def require_authentication
    authenticate!
  end

  def authenticate!
    user = current_user
    unless user
      render json: { error: "Authentication required" }, status: :unauthorized
      return
    end
    unless current_user_active?
      render json: { error: "Account locked or deactivated" }, status: :forbidden
      return
    end
  end

  # ★ Main admin check – unchanged, but now we add a more flexible version below
  def require_admin!
    return if current_user_active? && current_user&.admin?
    render json: { error: "Admin access required" }, status: :forbidden
  end

  # ★ NEW: Allow either main admin OR sub-admin with permission for a section
  def require_admin_or_permission!(section)
    return if current_user_active? && (current_user&.admin? || current_user&.sub_admin? && current_user.permissions.include?(section.to_s))
    render json: { error: "Admin or permission access required" }, status: :forbidden
  end

  # ★ NEW: Allow only sub-admin with permission (or main admin)
  def require_permission!(section)
    return if current_user_active? && (current_user&.admin? || (current_user&.sub_admin? && current_user.permissions.include?(section.to_s)))
    render json: { error: "Permission required" }, status: :forbidden
  end

  def require_seller!
    return if current_user_active? && current_user&.seller? && current_vendor&.approved?
    render json: { error: "Active seller account required" }, status: :forbidden
  end

  def require_buyer!
    return if current_user_active? && (current_user&.buyer? || current_user&.seller?)
    render json: { error: "Buyer account required" }, status: :forbidden
  end

  # ---------- Current User & Vendor – zero-trust from token ----------
  def current_user
    @current_user ||= begin
      if request.format.json?
        user_from_token
      else
        user_from_session
      end
    end
  end

  def current_vendor
    @current_vendor
  end

  # ---------- Status Checks ----------
  def logged_in?
    current_user.present?
  end
  alias authenticated? logged_in?

  def current_user_active?
    current_user && !current_user.locked? && !current_user.deactivated?
  end

  def ensure_active_user
    head :forbidden unless current_user_active?
  end

  def admin?
    current_user_active? && current_user&.admin?
  end

  def seller?
    current_user_active? && current_user&.seller?
  end

  def buyer?
    current_user_active? && (current_user&.buyer? || current_user&.seller?)
  end

  def sub_admin?
    current_user_active? && current_user&.sub_admin?
  end

  private

  def user_from_token
    token = extract_token
    return nil unless token

    decoded = JsonWebToken.decode_access(token)
    return nil unless decoded

    user = User.find_by(id: decoded[:user_id])
    return nil unless user

    # Verify user hasn't been deactivated/locked since token issued
    return nil if user.locked? || user.deactivated?

    # Set current_vendor from token (zero-trust, no extra DB hit)
    @current_vendor = Vendor.find_by(id: decoded[:vendor_id]) if decoded[:vendor_id]

    user
  end

  def user_from_session
    user = User.find_by(id: session[:user_id]) if session[:user_id].present?
    return nil unless user

    # Also set current_vendor for web/session authentication
    @current_vendor = Vendor.find_by(user_id: user.id) if user.seller?

    user
  end

  def extract_token
    header = request.headers['Authorization']&.strip
    header&.gsub(/\ABearer\s+/i, '') || request.headers['X-Auth-Token']
  end
end