# app/models/user.rb

class User < ApplicationRecord
  has_secure_password

  # --- JSONB default for permissions (for sub-admins) ---
  attribute :permissions, :jsonb, default: []

  # --- Enums ---
  enum :status, { active: 0, inactive: 1, banned: 2 }, prefix: true

  # --- Associations ---
  has_many :sessions, dependent: :destroy
  has_one :vendor, dependent: :destroy       # seller profile
  has_one :cart, dependent: :destroy
  has_one :wishlist, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :addresses, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :comparisons, dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_many :price_alerts, dependent: :destroy
  has_many :recently_vieweds, dependent: :destroy
  has_many :return_requests, dependent: :destroy
  has_many :user_consents, dependent: :destroy

  belongs_to :logistics_partner, optional: true

  has_one_attached :business_license

  # --- Callbacks ---
  before_create :ensure_buyer_role
  before_create :set_default_status
  before_validation :normalize_email, if: -> { email.present? }

  # --- Validations ---
  # Phone: required for non-sub-admin users, optional for sub-admins.
  validates :phone,
            presence: true,
            format: { with: /\A\+251[97]\d{8}\z/,
                      message: "must be a valid Ethiopian phone number" },
            unless: :sub_admin?

  validates :phone,
            uniqueness: true,
            allow_blank: true

  # Email: optional for regular users, required and unique for sub-admins.
  validates :email,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP },
            if: :sub_admin?

  validates :full_name, presence: true

  validates :password, length: { minimum: 8 },
                     format: {
                       with: /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[[:^alnum:]])/x,
                       message: "must include at least one uppercase letter, one lowercase letter, one number, and one special character"
                     },
                     if: :password_digest_changed?

  # Seller validations (only when role includes seller)
  validates :national_id, presence: true, if: :seller?
  validates :shop_name, presence: true, if: :seller?
  validates :shop_location, presence: true, if: :seller?

  # --- Bitmask Roles (buyer=1, seller=2, admin=4, sub_admin=8) ---
  ROLES = { 'buyer' => 1, 'seller' => 2, 'admin' => 4, 'sub_admin' => 8 }.freeze

  ROLES.each do |role_name, bit|
    define_method "#{role_name}?" do
      (role_mask & bit) == bit
    end
  end

  def add_role(role_name)
    bit = ROLES[role_name.to_s]
    update(role_mask: role_mask | bit) if bit
  end

  def remove_role(role_name)
    bit = ROLES[role_name.to_s]
    update(role_mask: role_mask & ~bit) if bit
  end

  def roles
    ROLES.select { |_name, bit| role_mask & bit == bit }.keys
  end

  def roles=(role_list)
    new_mask = Array(role_list).map { |r| ROLES[r.to_s] }.compact.reduce(0, :|)
    self.role_mask = new_mask
  end

  # ── Permission helpers for sub-admins ────────────────────
  def allowed_section?(section)
    return true if admin?
    return false unless sub_admin?
    permissions.include?(section.to_s)
  end

  # --- State helpers ---
  def deactivated?
    status_inactive? || status_banned?
  end

  def locked?
    locked_until.present? && locked_until > Time.current
  end

  def active_for_authentication?
    !locked? && !deactivated?
  end

  def new_user?
    welcomed_at.nil?
  end

  # --- OTP ---
  def generate_otp!
    self.otp_code = sprintf('%06d', rand(1000000))
    self.otp_expires_at = 5.minutes.from_now
    save!
  end

  def verify_otp(code)
    return false if otp_expires_at.nil? || Time.current > otp_expires_at
    return false if otp_code != code
    update!(phone_verified: true, otp_code: nil, otp_expires_at: nil)
    true
  end

  # --- Lockout ---
  def record_failed_attempt!
    increment!(:failed_attempts)
    if failed_attempts >= 5
      update!(locked_until: 30.minutes.from_now)
    end
  end

  def reset_failed_attempts!
    update!(failed_attempts: 0, locked_until: nil)
  end

  # If lock has expired, clear the failed attempts count so a new lockout starts fresh.
  # Call this before attempting authentication.
  def clear_expired_lock!
    if locked_until.present? && locked_until <= Time.current
      update!(locked_until: nil, failed_attempts: 0)
    end
  end

  # --- Account Deletion & Soft Delete ---
  # Soft delete: keep the record but anonymise personal data and block login.
  # This preserves order history and financial records.
  def deactivate_account!
    update_columns(
      status: User.statuses[:inactive],
      phone: "deleted_#{SecureRandom.hex(6)}_#{id}",  # no longer valid, avoids unique conflict
      email: nil,
      full_name: "Deleted User",
      national_id: nil,
      refresh_token_digest: nil,
      fcm_token: nil,
      otp_code: nil,
      otp_expires_at: nil,
      phone_verified: false
    )
    # Revoke all sessions
    sessions.destroy_all
    true
  end

  # Hard delete (admin only) – use with caution as it removes order history.
  def hard_delete!
    transaction do
      # Nullify references to this user in orders, reviews, etc.
      orders.update_all(user_id: nil)  # or keep a ghost user
      reviews.update_all(user_id: nil)
      return_requests.update_all(user_id: nil)
      messages_sent.update_all(sender_id: nil) if respond_to?(:messages_sent)
      messages_received.update_all(receiver_id: nil) if respond_to?(:messages_received)
      destroy!
    end
  end

  # --- Consent Management ---
  def needs_agreement_update?
    LegalPage.published.each do |page|
      consent = user_consents.find_by(agreement_type: page.key)
      return true unless consent && consent.agreement_version >= page.version
    end
    false
  end

  def record_consent!(agreement_type, version, ip = nil)
    consent = user_consents.find_or_initialize_by(agreement_type: agreement_type)
    consent.update!(agreement_version: version, accepted_at: Time.current, ip_address: ip)
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def ensure_buyer_role
    # Add buyer role only if no role bits are set at all.
    self.role_mask = (role_mask | ROLES['buyer']) if role_mask.to_i.zero?
  end

  def set_default_status
    self.status ||= :active
  end
end