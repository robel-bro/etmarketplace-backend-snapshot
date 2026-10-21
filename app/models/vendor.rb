# app/models/vendor.rb

class Vendor < ApplicationRecord
  belongs_to :user
  belongs_to :membership_plan, optional: true

  has_one_attached :license_document
  has_one_attached :id_document
  has_one_attached :logo
  has_one_attached :banner
  has_one_attached :tin_certificate

  has_many :products, dependent: :destroy
  has_many :packages, dependent: :destroy
  has_many :orders, dependent: :restrict_with_error
  has_many :payouts, dependent: :destroy
  has_many :reviews, as: :reviewable, dependent: :destroy

  scope :bulk_suppliers, -> { where(is_bulk_supplier: true) }
  scope :suspended, -> { where(status: :suspended) }

  enum :status, {
    pending: 0,
    approved: 1,
    rejected: 2,
    suspended: 3
  }

  enum :payout_method, {
    telebirr: 0,
    bank: 1
  }, prefix: :payout

  attribute :premium, :boolean, default: false
  attribute :premium_expires_at, :datetime
  attribute :average_processing_hours, :integer, default: 24

  validates :business_name, presence: true
  validates :national_id, presence: true, uniqueness: { allow_nil: true }, if: :approved?
  validates :business_address, presence: true

  validates :payout_method, presence: true, if: :approved?

  with_options if: -> { approved? && payout_telebirr? } do
    validates :telebirr_number, presence: true
  end

  with_options if: -> { approved? && payout_bank? } do
    validates :bank_account_number, presence: true
    validates :bank_name, presence: true
  end

  after_update :set_approved_at, if: -> { saved_change_to_status?(to: 'approved') }
  after_update :set_rejected_at, if: -> { saved_change_to_status?(to: 'rejected') }

  # ★ Accepting orders flag – required by Product model
  # Migrate: add column `accepting_orders` boolean, default true
  def accepting_orders?
    self[:accepting_orders] && status == 'approved'
  end

  # ─────────────── Membership Management ───────────────
  # ★ FIXED: Include plan.active? to ensure inactive plans are not considered active.
  # This aligns with Product#effective_commission_rate and prevents commission inconsistency.
  def membership_active?
    membership_plan.present? &&
      membership_plan.active? &&
      membership_expires_at.present? &&
      Time.current < membership_expires_at
  end

  def assign_membership_plan(plan)
    attrs = {
      membership_plan: plan,
      membership_expires_at: plan.duration_days.days.from_now,
      commission_rate: plan.commission_rate.presence || commission_rate
    }
    update!(attrs)
  end

  def remove_membership!
    update!(
      membership_plan: nil,
      membership_expires_at: nil,
      commission_rate: nil
    )
  end

  def featured_active?
    return false unless featured?
    featured_until.nil? || Time.current < featured_until
  end

  def sponsored_slots_remaining
    return 0 unless membership_active?
    max = membership_plan.sponsored_product_limit.to_i
    current = products.where(sponsored: true).count
    [max - current, 0].max
  end

  def effective_commission_rate
    if membership_active? && membership_plan.commission_rate.present?
      membership_plan.commission_rate
    else
      commission_rate
    end
  end

  # ─────────────── Pickup Readiness ───────────────
  def ready_for_pickup?
    pickup_ready && (pickup_ready_deadline.nil? || Time.current <= pickup_ready_deadline)
  end

  def set_pickup_deadline!
    update(pickup_ready_deadline: Time.current + preparation_time_minutes.minutes)
  end

  # ─────────────── Health Methods ───────────────
  def update_order_stats!(reference_date = 30.days.ago)
    orders_window = orders.where('created_at >= ?', reference_date)

    self.total_orders_count     = orders_window.count
    self.declined_orders_count  = orders_window.where(status: :cancelled)
                                              .where.not(rejected_at: nil).count
    self.unanswered_orders_count = orders_window.where(status: :pending_acceptance)
                                              .where('acceptance_deadline < ?', Time.current).count

    accepted_orders = orders_window.where.not(accepted_at: nil)
    if accepted_orders.any?
      total_hours = accepted_orders.sum { |o| ((o.accepted_at - o.created_at) / 1.hour).round(2) }
      self.avg_response_time_hours = (total_hours / accepted_orders.count.to_f).round(2)
    else
      self.avg_response_time_hours = 0.0
    end

    save!
  end

  def check_health!
    return unless approved?

    settings = Setting.get('seller_health') || {}
    inactivity_days           = settings['inactivity_days']&.to_i           || 30
    decline_rate_threshold    = settings['decline_rate_threshold']&.to_f    || 50.0
    response_time_threshold   = settings['response_time_threshold_hours']&.to_f || 48.0
    unanswered_threshold      = settings['unanswered_orders_threshold']&.to_i   || 5

    reasons = []

    last_activity = last_login_at || user.created_at
    if last_activity < inactivity_days.days.ago
      reasons << "No login for #{inactivity_days} days"
    end

    if total_orders_count.to_i > 0
      decline_rate = (declined_orders_count.to_f / total_orders_count) * 100
      if decline_rate > decline_rate_threshold
        reasons << "Decline rate #{decline_rate.round(1)}% exceeds #{decline_rate_threshold}%"
      end
    end

    if avg_response_time_hours.to_f > response_time_threshold
      reasons << "Avg response time #{avg_response_time_hours}h exceeds #{response_time_threshold}h"
    end

    if unanswered_orders_count.to_i > unanswered_threshold
      reasons << "#{unanswered_orders_count} unanswered orders (threshold: #{unanswered_threshold})"
    end

    if reasons.any?
      suspend!(reasons.join('; '))
    end
  end

  def suspend!(reason)
    update!(status: :suspended, suspension_reason: reason)
    products.where(status: :active).update_all(status: :draft)
  end

  def unsuspend!
    update!(status: :approved, suspension_reason: nil)
  end

  # ─────────────── Attachment URL Helpers ───────────────
  def logo_url
    attachment_url(logo)
  end

  def banner_url
    attachment_url(banner)
  end

  def license_document_url
    attachment_url(license_document)
  end

  def id_document_url
    attachment_url(id_document)
  end

  def tin_certificate_url
    attachment_url(tin_certificate)
  end

  # ─────────────── Public helpers ───────────────
  def average_rating
    reviews.average(:rating)&.round(1) || 0.0
  end

  def total_reviews_count
    reviews.count
  end

  def products_count
    self[:products_count] || 0
  end

  def categories
    products.active.includes(:category).map(&:category).compact.uniq
  end

  def discounted_products(limit = 10)
    products.active.where(is_flash_sale: true).limit(limit)
  end

  def membership_tier
    return nil unless membership_plan&.active?
    name = membership_plan.name.downcase
    %w[silver gold platinum].include?(name) ? name : nil
  end

  def badge
    membership_tier
  end

  def display_badge
    if membership_plan&.active?
      return membership_plan.badge_text if membership_plan.badge_text.present?
      tier = membership_plan.name.downcase
      %w[silver gold platinum].include?(tier) ? "#{tier.capitalize} Seller" : nil
    else
      nil
    end
  end

  def total_sales_count
    read_attribute(:total_sales_count_cache) || 0
  end

  def enterprise?
    is_bulk_supplier? || (business_type == 'company') rescue false
  end

  def premium?
    premium && premium_expires_at.present? && premium_expires_at > Time.current
  end

  def return_policy
    read_attribute(:return_policy) || "We accept returns within 14 days of delivery."
  end

  def shipping_policy
    read_attribute(:shipping_policy) || "Orders are shipped within 2 business days."
  end

  def payment_policy
    read_attribute(:payment_policy) || "We accept Telebirr, Chapa, and cash on delivery."
  end

  # ─────────── Payout & Balance Methods ─────────────
  def available_balance
    released = FinancialLedger.where(
      ledgerable: self,
      credit_account: FinancialLedgerService::ACCOUNTS[:seller_receivable]
    ).sum(:amount)

    paid = FinancialLedger.where(
      ledgerable: self,
      debit_account: FinancialLedgerService::ACCOUNTS[:seller_receivable]
    ).sum(:amount)

    clawbacks = FinancialLedger.where(
      ledgerable: self,
      debit_account: FinancialLedgerService::ACCOUNTS[:refunds_receivable]
    ).sum(:amount)

    [released - paid - clawbacks, 0].max
  end

  def payout_details_snapshot
    {
      method: payout_method,
      telebirr_account: telebirr_number,
      bank_name: bank_name,
      bank_account_number: bank_account_number
    }
  end

  private

  def set_approved_at
    update_column(:approved_at, Time.current)
  end

  def set_rejected_at
    update_column(:rejected_at, Time.current)
  end

  def attachment_url(attachment)
    return nil unless attachment.attached?

    host = Rails.application.routes.default_url_options[:host]
    if host.present?
      Rails.application.routes.url_helpers.rails_blob_url(attachment, host: host, only_path: false)
    else
      Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
    end
  end
end