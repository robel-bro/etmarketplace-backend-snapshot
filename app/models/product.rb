# app/models/product.rb
class Product < ApplicationRecord
  class InsufficientStockError < StandardError; end

  attribute :variants_data, :jsonb, default: []
  attribute :product_attributes, :jsonb, default: {}
  attribute :stock_reserved, :integer, default: 0
  attribute :trending_score, :float, default: 0.0

  searchkick word_start: [:title],
             filterable: [
               :category_id, :status, :brand, :price,
               :rating, :delivery_type, :bulk_enabled, :vendor_status
             ],
             synonyms: SEARCHKICK_SYNONYMS,
             searchable: [:title, :description, :brand, :category_name, :product_attributes_text]

  after_commit :reindex_with_rescue
  after_save :sync_variants_to_table, if: :saved_change_to_variants_data?

  # ── Associations ──
  belongs_to :vendor, counter_cache: true
  belongs_to :category

  has_many_attached :images
  has_many_attached :videos

  has_many :reviews, dependent: :destroy
  has_many :questions, dependent: :destroy
  has_many :line_items, dependent: :restrict_with_error
  has_many :product_attribute_values, dependent: :destroy
  has_many :reservations, dependent: :destroy
  has_many :product_variants, dependent: :destroy

  accepts_nested_attributes_for :product_variants, allow_destroy: true

  store_accessor :product_attributes, :size, :color, :brand, :material, :specs

  before_validation :clear_shipping_subsidy_if_not_paying
  before_validation :normalize_variants_data
  before_validation :set_price_from_variant, on: [:create, :update]

  scope :in_stock, -> {
    where(<<~SQL.squish)
      (
        (products.stock - COALESCE(products.stock_reserved, 0) > 0
         AND (
           products.variants_data IS NULL
           OR products.variants_data = '[]'
           OR NOT EXISTS (
             SELECT 1 FROM jsonb_array_elements(products.variants_data) v
             WHERE (v->'attributes')::jsonb IS NOT NULL
               AND (v->'attributes')::jsonb <> '{}'::jsonb
           )
         ))
        OR
        (products.bulk_enabled = true AND products.stock IS NULL
         AND (
           products.variants_data IS NULL
           OR products.variants_data = '[]'
           OR NOT EXISTS (
             SELECT 1 FROM jsonb_array_elements(products.variants_data) v
             WHERE (v->'attributes')::jsonb IS NOT NULL
               AND (v->'attributes')::jsonb <> '{}'::jsonb
           )
         ))
        OR EXISTS (
          SELECT 1 FROM product_variants pv
          WHERE pv.product_id = products.id
            AND (pv.unlimited_stock = TRUE OR (pv.stock - COALESCE(pv.reserved, 0)) > 0)
            AND EXISTS (
              SELECT 1 FROM jsonb_array_elements(products.variants_data) v
              WHERE (v->'attributes')::jsonb IS NOT NULL
                AND (v->'attributes')::jsonb <> '{}'::jsonb
            )
        )
      )
    SQL
  }

  scope :visible, -> { where(status: :active).in_stock }

  enum :status, { draft: 0, active: 1, archived: 2 }

  attribute :is_flash_sale, :boolean, default: false
  attribute :is_super_deal, :boolean, default: false
  attribute :is_trending, :boolean, default: false
  attribute :is_hot_deal, :boolean, default: false

  attribute :views_count, :integer, default: 0
  attribute :sold_count, :integer, default: 0
  attribute :flash_sale_price, :decimal, precision: 10, scale: 2
  attribute :flash_sale_ends_at, :datetime
  attribute :super_deal_price, :decimal, precision: 10, scale: 2
  attribute :super_deal_ends_at, :datetime

  attribute :original_price, :decimal, precision: 10, scale: 2
  attribute :discount, :integer, default: 0
  attribute :discount_type, :string
  attribute :discount_value, :decimal, precision: 10, scale: 2

  attribute :stock, :integer, default: 0
  attribute :free_shipping, :boolean, default: false
  attribute :seller_pays_shipping, :boolean, default: false
  attribute :shipping_subsidy_type, :string
  attribute :shipping_subsidy_value, :decimal, precision: 10, scale: 2

  attribute :bulk_enabled, :boolean, default: false
  attribute :minimum_bulk_quantity, :integer, default: 1
  attribute :max_quantity_per_day, :integer

  attribute :rating, :decimal, precision: 2, scale: 1, default: 0.0
  attribute :reviews_count, :integer, default: 0

  validates :title, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }, allow_nil: true
  validates :reviews_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :sold_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :minimum_bulk_quantity, numericality: { only_integer: true, greater_than: 0 }, if: :bulk_enabled?
  validates :max_quantity_per_day, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # Required dimensions & weight for delivery calculation
  validates :weight_kg, presence: true, numericality: { greater_than: 0 }
  validates :length_cm, presence: true, numericality: { greater_than: 0 }
  validates :width_cm, presence: true, numericality: { greater_than: 0 }
  validates :height_cm, presence: true, numericality: { greater_than: 0 }

  validates :discount_type, inclusion: { in: %w[percent flat] }, allow_nil: true
  validates :discount_value, numericality: { greater_than: 0, less_than_or_equal_to: 100 },
            if: -> { discount_type == 'percent' && discount_value.present? }
  validates :discount_value, numericality: { greater_than: 0 },
            if: -> { discount_type == 'flat' && discount_value.present? }

  validates :shipping_subsidy_type, inclusion: { in: %w[full percent] }, allow_nil: true
  validates :shipping_subsidy_value, numericality: { greater_than: 0, less_than_or_equal_to: 100 },
            if: -> { shipping_subsidy_type == 'percent' && shipping_subsidy_value.present? }

  validate :videos_content_type, :videos_size, :images_content_type, :images_size
  validate :must_have_price_or_variants

  # ── SCOPES ──
  scope :new_arrivals,   -> { visible.where(created_at: 30.days.ago..).where(is_flash_sale: false, is_super_deal: false).order(created_at: :desc) }
  scope :smart_sort,     -> { order(trending_score: :desc, views_count: :desc, sold_count: :desc, rating: :desc) }
  scope :trending,       -> { visible.smart_sort }
  scope :best_sellers,   -> { visible.order(sold_count: :desc, rating: :desc) }
  scope :hot_deals,      -> { visible.where('sold_count > 0 AND stock > 0').where(is_flash_sale: false, is_super_deal: false).smart_sort }
  scope :flash_sales,    -> { visible.where(is_flash_sale: true).where('flash_sale_ends_at > ?', Time.current).order(flash_sale_ends_at: :asc) }
  scope :super_deals,    -> { visible.where(is_super_deal: true).where('super_deal_ends_at > ?', Time.current).order(super_deal_ends_at: :asc) }
  scope :bulk_only,      -> { where(bulk_enabled: true) }
  scope :popular,        -> { visible.smart_sort }
  scope :highest_rated,  -> { visible.order(rating: :desc, sold_count: :desc) }
  scope :by_membership,  -> {
    joins(:vendor).joins("LEFT JOIN membership_plans ON membership_plans.id = vendors.membership_plan_id")
      .merge(visible)
      .order(Arel.sql("COALESCE(membership_plans.price, 0) DESC, products.rating DESC, products.sold_count DESC"))
  }

  def self.products_for_section(section_type)
    case section_type
    when 'new_arrivals' then new_arrivals
    when 'trending' then trending
    when 'best_sellers' then best_sellers
    when 'hot_deals' then hot_deals
    when 'flash_sale' then flash_sales
    when 'super_deal' then super_deals
    else none
    end
  end

  def self.recompute_dynamic_deals!
    # unchanged
  end

  # ── Smart trending score calculation ──
  def self.update_trending_scores!
    Product.find_each(batch_size: 500) do |product|
      recent_sales = product.line_items.joins(:order)
                            .where('orders.created_at >= ?', 7.days.ago)
                            .where.not(orders: { status: ['cancelled', 'returned'] })
                            .sum(:quantity)
      age_days = [(Time.current - product.created_at) / 1.day, 1].min
      age_decay = 1.0 / Math.sqrt(age_days)
      score = (product.views_count * 0.3) + (product.sold_count * 0.5) + (recent_sales * 0.2)
      score *= age_decay
      product.update_column(:trending_score, score.round(4))
    end
  end

  # ── Discount & Price Helpers ──
  def apply_discount_to(base_price)
    return base_price if base_price.nil? || base_price <= 0
    return base_price if discount_type.blank? || discount_value.blank? || discount_value <= 0
    case discount_type
    when 'percent'
      (base_price * (1 - discount_value / 100.0)).round(2)
    when 'flat'
      [base_price - discount_value, 0].max
    else
      base_price
    end
  end

  def effective_price_for(base_price)
    return base_price if base_price.nil?
    if is_flash_sale? && flash_sale_ends_at.present? && flash_sale_ends_at > Time.current
      flash_sale_price.presence || base_price
    elsif is_super_deal? && super_deal_ends_at.present? && super_deal_ends_at > Time.current
      super_deal_price.presence || base_price
    else
      apply_discount_to(base_price)
    end
  end

  def current_price
    effective_price_for(price)
  end

  alias effective_selling_price current_price

  def discount_percentage
    if discount_type == 'percent' && discount_value.present?
      discount_value.to_i
    elsif original_price.present? && original_price > 0 && price.present? && original_price > price
      ((original_price - price) / original_price * 100).round
    else
      discount.to_i
    end
  end

  def increment_views!
    increment!(:views_count)
  end

  # ── Media Helpers ──
  def image_urls
    @image_urls ||= begin
      host = Rails.application.routes.default_url_options[:host]
      if host.present?
        images.map { |img| Rails.application.routes.url_helpers.rails_blob_url(img, only_path: false) }
      else
        images.map { |img| Rails.application.routes.url_helpers.rails_blob_path(img, only_path: true) }
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to generate image URLs for product #{id}: #{e.message}"
      []
    end
  end

  def video_urls
    @video_urls ||= begin
      host = Rails.application.routes.default_url_options[:host]
      if host.present?
        videos.map { |v| Rails.application.routes.url_helpers.rails_blob_url(v, only_path: false) }
      else
        videos.map { |v| Rails.application.routes.url_helpers.rails_blob_path(v, only_path: true) }
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to generate video URLs for product #{id}: #{e.message}"
      []
    end
  end

  def first_image_url
    image_urls.first
  end

  # ── Stock & Availability ──
  def variant_product?
    product_variants.loaded? ? product_variants.any? : product_variants.exists?
  end

  def has_real_variants?
    return true if variant_product? && product_variants.any? { |pv| pv.variant_attributes.present? && pv.variant_attributes.values.any?(&:present?) }
    return false unless variants_data.is_a?(Array) && variants_data.present?
    variants_data.any? { |v| v.is_a?(Hash) && v['attributes'].is_a?(Hash) && v['attributes'].values.any?(&:present?) }
  end

  def has_variants?
    has_real_variants?
  end

  def variants_count
    product_variants.size
  end

  # ★ Physical available stock (NO daily cap)
  def available_stock
    physical = if variant_product?
                 variants = product_variants.to_a
                 if variants.all?(&:unlimited_stock?)
                   Float::INFINITY
                 else
                   limited_variants = variants.reject(&:unlimited_stock?)
                   limited_variants.sum(&:available_stock)
                 end
               else
                 return Float::INFINITY if bulk_enabled? && stock.nil?
                 [(stock - stock_reserved), 0].max
               end

    [physical, 0].max
  end

  def cumulative_physical_stock
    if variant_product?
      variants = product_variants.to_a
      if variants.all?(&:unlimited_stock?)
        Float::INFINITY
      else
        variants.reject(&:unlimited_stock?).sum(&:stock)
      end
    elsif bulk_enabled? && stock.nil?
      Float::INFINITY
    else
      stock
    end
  end

  def stock_display
    return "Unlimited" if available_stock == Float::INFINITY
    return "0" if available_stock <= 0
    available_stock.to_i.to_s
  end

  def remaining_daily_quantity
    return nil unless max_quantity_per_day.present?
    [max_quantity_per_day - today_quantity_sold, 0].max
  end

  def find_variant(attributes)
    return nil if attributes.blank?
    product_variants.find_by(variant_attributes: attributes)
  end

  def out_of_stock?
    available_stock <= 0
  end

  def can_fulfill?(quantity, variant: nil)
    if variant.present?
      pv = find_variant(variant)
      return false unless pv
      return true if pv.unlimited_stock?
      (pv.stock - pv.reserved) >= quantity
    else
      available_stock == Float::INFINITY || available_stock >= quantity
    end
  end

  # ── Stock Operations (atomic) ──
  def reserve_stock!(quantity, variant_attributes = nil)
    if variant_attributes.present? && variant_product?
      with_lock do
        variant = product_variants.find_by!(variant_attributes: variant_attributes)
        variant.with_lock do
          return false if quantity <= 0

          if max_quantity_per_day.present?
            sold_today = today_quantity_sold
            remaining = max_quantity_per_day - sold_today
            raise InsufficientStockError, "Daily quantity limit reached" if remaining < quantity
          end

          unless variant.unlimited_stock?
            available = variant.stock - variant.reserved
            raise InsufficientStockError, "Not enough stock for variant #{variant.id}" if available < quantity
            variant.update_column(:reserved, variant.reserved + quantity)
          end
        end
      end
    else
      with_lock do
        return false if quantity <= 0
        return true if bulk_enabled? && stock.nil?

        if max_quantity_per_day.present?
          sold_today = today_quantity_sold
          remaining = max_quantity_per_day - sold_today
          raise InsufficientStockError, "Daily quantity limit reached" if remaining < quantity
        end

        available = stock - stock_reserved
        raise InsufficientStockError, "Not enough stock for product #{id}" if available < quantity
        update_column(:stock_reserved, stock_reserved + quantity)
      end
    end
    true
  end

  def release_stock!(quantity, variant_attributes = nil)
    if variant_attributes.present? && variant_product?
      with_lock do
        variant = product_variants.find_by!(variant_attributes: variant_attributes)
        variant.with_lock do
          if quantity > 0 && !variant.unlimited_stock?
            variant.update_column(:reserved, [variant.reserved - quantity, 0].max)
          end
        end
      end
    else
      with_lock do
        if quantity > 0 && !(bulk_enabled? && stock.nil?)
          update_column(:stock_reserved, [stock_reserved - quantity, 0].max)
        end
      end
    end
  end

  def restock!(quantity, variant_attributes = nil)
    raise ArgumentError, "quantity must be positive" if quantity.to_i <= 0

    if variant_attributes.present? && variant_product?
      with_lock do
        variant = product_variants.find_by!(variant_attributes: variant_attributes)
        variant.with_lock do
          unless variant.unlimited_stock?
            variant.update_column(:stock, variant.stock.to_i + quantity.to_i)
            variant.update_column(:reserved, [(variant.reserved || 0) - quantity.to_i, 0].max)
          end
        end
      end
    else
      with_lock do
        unless bulk_enabled? && stock.nil?
          update_column(:stock, (stock || 0) + quantity.to_i)
          update_column(:stock_reserved, [(stock_reserved || 0) - quantity.to_i, 0].max)
        end
      end
    end
    true
  end

  # ── Commission & Vendor Helpers ──
  def effective_commission_rate
    if vendor&.membership_active? && vendor.membership_plan.commission_rate.present?
      return vendor.membership_plan.commission_rate
    end

    if vendor&.commission_rate.present?
      return vendor.commission_rate
    end

    commission_settings = Setting.get('commission') || {}
    default_rate = commission_settings['defaultCommission'] || 0
    category_overrides = commission_settings['categoryCommission'] || {}
    cat_id = category_id.to_s
    category_overrides[cat_id] || default_rate
  end

  def seller_pays_shipping?
    self[:seller_pays_shipping] && shipping_subsidy_type.present?
  end

  def free_delivery?
    free_shipping? || (seller_pays_shipping? && shipping_subsidy_type == 'full')
  end

  def delivery_label
    if free_delivery?
      "Free Delivery"
    elsif seller_pays_shipping? && shipping_subsidy_type == 'percent'
      "#{shipping_subsidy_value.to_i}% Off Delivery"
    else
      "Paid Delivery"
    end
  end

  # ── Daily Limit Helpers ──
  def self.today_quantity_sold_map(product_ids)
    return {} if product_ids.blank?
    LineItem.joins(:order)
            .where(product_id: product_ids)
            .where('orders.created_at >= ?', Date.current)
            .where.not(orders: { status: ['cancelled', 'returned'] })
            .group(:product_id)
            .sum(:quantity)
  end

  def today_quantity_sold(preloaded_map = nil)
    if preloaded_map
      preloaded_map[id] || 0
    else
      line_items.joins(:order)
                .where('orders.created_at >= ?', Date.current)
                .where.not(orders: { status: ['cancelled', 'returned'] })
                .sum(:quantity)
    end
  end

  def daily_quantity_limit_reached?(additional_qty = 0, preloaded_sold = nil)
    sold = today_quantity_sold(preloaded_sold)
    max_quantity_per_day.present? && (sold + additional_qty) > max_quantity_per_day
  end

  def can_be_ordered?(quantity = 1, preloaded_sold = nil)
    return false if draft? || archived?
    return false unless vendor&.accepting_orders?
    return false if daily_quantity_limit_reached?(quantity, preloaded_sold)
    can_fulfill?(quantity)
  end

  def unavailable_reason(preloaded_sold = nil)
    return 'Product is not active' if draft? || archived?
    return 'Vendor is not accepting orders' unless vendor&.accepting_orders?
    return 'Daily quantity limit reached – try again tomorrow' if daily_quantity_limit_reached?(0, preloaded_sold)
    if available_stock <= 0
      'Out of stock'
    end
  end

  # ── Searchkick Data ──
  def search_data
    {
      title: title,
      description: description,
      brand: product_attributes&.dig('brand')&.downcase,
      category_name: category&.name,
      category_id: category_id,
      product_attributes_text: product_attributes&.values&.compact&.join(' '),
      status: status,
      price: price,
      effective_price: current_price,
      views_count: views_count,
      sold_count: sold_count,
      trending_score: trending_score,
      created_at: created_at,
      vendor_id: vendor_id,
      vendor_status: vendor.status,
      rating: rating,
      delivery_type: delivery_label,
      bulk_enabled: bulk_enabled,
      minimum_bulk_quantity: minimum_bulk_quantity
    }
  end

  private

  def clear_shipping_subsidy_if_not_paying
    unless seller_pays_shipping?
      self.shipping_subsidy_type = nil
      self.shipping_subsidy_value = nil
    end
  end

  def normalize_variants_data
    self.variants_data = (variants_data || []).map do |v|
      next v unless v.is_a?(Hash)
      v = v.dup
      v['attributes'] = (v['attributes'] || {}).transform_keys(&:to_s)
      v['unlimited_stock'] = v['unlimited_stock'].present? && v['unlimited_stock'] != false
      v
    end
  end

  def set_price_from_variant
    return unless variants_data.is_a?(Array)
    prices = variants_data.filter_map do |v|
      v['price'].to_f if v.is_a?(Hash) && v['price'].present? && v['price'].to_f > 0
    end
    self.price = prices.min if prices.any?
  end

  def must_have_price_or_variants
    return if price.present? && price.to_f > 0
    return if has_real_variants? && variants_data.any? { |v| v.is_a?(Hash) && v['price'].to_f > 0 }
    errors.add(:base, "Product must have a price or at least one priced variant")
  end

  def reindex_with_rescue
    reindex(mode: :async)
  rescue Faraday::ConnectionFailed, Elasticsearch::Transport::Transport::Error => e
    Rails.logger.warn "Searchkick indexing skipped for Product #{id}: #{e.message}"
  end

  # ★ Updated to sync logistics fields from variants_data
  def sync_variants_to_table
    ActiveRecord::Base.transaction do
      current_map = product_variants.pluck(:id, :variant_attributes).to_h { |id, attrs| [attrs, id] }

      submitted_attrs = (variants_data || []).filter_map do |v|
        next unless v.is_a?(Hash) && v['price'].present?
        attrs = (v['attributes'] || {}).transform_keys(&:to_s)
        unlimited = v['unlimited_stock'].present? && v['unlimited_stock'] != false

        # ★ New logistics fields extraction
        logistics = {
          price: v['price'].to_f,
          stock: unlimited ? 0 : (v['stock'].presence&.to_i || 0),
          unlimited_stock: unlimited,
          variant_attributes: attrs,
          sku: v['sku'].presence,
          minimum_bulk_quantity: bulk_enabled? ? minimum_bulk_quantity : nil,
          # New columns
          weight_kg: v['weight_kg'].presence&.to_f,
          length_cm: v['length_cm'].presence&.to_f,
          width_cm: v['width_cm'].presence&.to_f,
          height_cm: v['height_cm'].presence&.to_f,
          refrigerated: v['refrigerated'].present? ? v['refrigerated'].to_s.downcase == 'true' : false,
          fragile: v['fragile'].present? ? v['fragile'].to_s.downcase == 'true' : false
        }

        logistics
      end

      submitted_attrs = submitted_attrs.uniq { |attrs| attrs[:variant_attributes] }

      submitted_attrs.each do |attrs|
        existing_id = current_map[attrs[:variant_attributes]]
        if existing_id
          product_variants.find(existing_id).update!(attrs)
          current_map.delete(attrs[:variant_attributes])
        else
          product_variants.create!(attrs)
        end
      end

      # For variants that were removed from variants_data:
      # Only destroy if not referenced in any cart, order, package, or reservation.
      current_map.each do |attrs, variant_id|
        variant = product_variants.find_by(id: variant_id)
        next unless variant

        referenced = CartItem.exists?(variant_attributes: attrs) ||
                     LineItem.exists?(variant_attributes: attrs) ||
                     PackageProduct.exists?(variant_attributes: attrs) ||
                     Reservation.exists?(variant_attributes: attrs)

        if referenced
          Rails.logger.warn "Product #{id}: Variant #{variant_id} (#{attrs.inspect}) is referenced and will not be destroyed. Keeping it."
        else
          variant.destroy!
        end
      end

      # ★ Sync product-level price and stock to reflect variants
      sync_product_aggregates_from_variants
    end
  end

  def sync_product_aggregates_from_variants
    return unless has_real_variants?

    # Minimum variant price
    prices = product_variants.map(&:price).compact
    self.price = prices.min if prices.any?

    # For variant products, product-level stock is redundant; set to nil to avoid stale values
    self.stock = nil
  end

  def videos_content_type
    videos.each do |video|
      unless video.content_type.in?(%w[video/mp4 video/webm video/quicktime])
        errors.add(:videos, "must be MP4, WebM, or MOV")
      end
    end
  end

  def videos_size
    videos.each do |video|
      if video.byte_size > 50.megabytes
        errors.add(:videos, "should be less than 50MB")
      end
    end
  end

  def images_content_type
    images.each do |image|
      unless image.content_type.in?(%w[image/png image/jpeg image/webp image/gif])
        errors.add(:images, "must be PNG, JPEG, WebP, or GIF")
      end
    end
  end

  def images_size
    images.each do |image|
      if image.byte_size > 5.megabytes
        errors.add(:images, "should be less than 5MB")
      end
    end
  end
end