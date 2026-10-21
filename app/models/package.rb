# app/models/package.rb
class Package < ApplicationRecord
  class InsufficientStockError < StandardError; end

  # JSONB defaults
  attribute :features, :jsonb, default: []
  attribute :trending_score, :float, default: 0.0
  attribute :stock_reserved, :integer, default: 0

  # ---------- Searchkick ----------
  searchkick word_start: [:name],
             filterable: [
               :category_ids, :status, :price, :vendor_id,
               :vendor_status, :free_delivery, :in_stock
             ],
             synonyms: SEARCHKICK_SYNONYMS,
             searchable: [:name, :description, :category_names]

  after_commit :reindex_with_rescue

  # ── Associations ──
  belongs_to :vendor, touch: true
  has_many :package_categories, dependent: :destroy
  has_many :categories, through: :package_categories

  has_many :package_products, dependent: :destroy, autosave: true
  has_many :products, through: :package_products

  has_many :reviews, as: :reviewable, dependent: :destroy
  has_many_attached :images
  has_many_attached :videos

  enum :status, { draft: 0, active: 1, archived: 2 }
  enum :discount_type, { percentage: 'percentage', fixed: 'fixed' }, prefix: true

  # Stock & bulk
  attribute :stock, :integer, default: 0
  attribute :bulk_enabled, :boolean, default: false

  # Shipping
  attribute :free_shipping,    :boolean, default: false
  attribute :seller_pays_shipping, :boolean, default: false
  attribute :shipping_subsidy_type, :string
  attribute :shipping_subsidy_value, :decimal, precision: 10, scale: 2

  validates :name, :price, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :categories, presence: true

  validates :shipping_subsidy_type, inclusion: { in: %w[full percent] }, allow_nil: true
  validates :shipping_subsidy_value, numericality: { greater_than: 0, less_than_or_equal_to: 100 },
            if: -> { shipping_subsidy_type == 'percent' && shipping_subsidy_value.present? }

  validate :images_content_type, :images_size, :videos_content_type, :videos_size
  validate :stock_cannot_exceed_max_possible, unless: -> { package_products.empty? }

  before_save :compute_original_price, if: -> {
    will_save_change_to_discount_value? || will_save_change_to_discount_type? || will_save_change_to_price?
  }

  # ── Scopes ──
  scope :in_stock, -> {
    where(<<~SQL.squish)
      (
        (packages.stock IS NOT NULL AND packages.stock - COALESCE(packages.stock_reserved, 0) > 0)
        OR
        (packages.bulk_enabled = true AND packages.stock IS NULL)
      )
      AND NOT EXISTS (
        SELECT 1
        FROM package_products pp
        JOIN products p ON p.id = pp.product_id
        WHERE pp.package_id = packages.id
          AND (
            (p.stock IS NOT NULL AND p.stock - COALESCE(p.stock_reserved, 0) <= 0
             AND NOT EXISTS (
               SELECT 1 FROM product_variants pv2
               WHERE pv2.product_id = p.id AND pv2.variant_attributes <> '{}'::jsonb
             )
            )
            OR
            (EXISTS (
               SELECT 1 FROM product_variants pv3
               WHERE pv3.product_id = p.id AND pv3.variant_attributes <> '{}'::jsonb
             )
             AND NOT EXISTS (
               SELECT 1 FROM product_variants pv4
               WHERE pv4.product_id = p.id
                 AND (pv4.unlimited_stock = TRUE OR (pv4.stock - COALESCE(pv4.reserved, 0)) > 0)
             )
            )
          )
      )
    SQL
  }

  scope :smart_sort, -> { order(trending_score: :desc, created_at: :desc) }

  scope :visible, -> {
    joins(:vendor).where(vendors: { status: :approved }).merge(in_stock)
  }

  # ── Stock helpers (variant‑aware) ──
  def maximum_possible_stock
    return 0 if package_products.empty?
    stocks = package_products.map { |pp| pp.available_stock }
    return Float::INFINITY if stocks.any? { |s| s == Float::INFINITY } && stocks.all? { |s| s == Float::INFINITY }
    stocks.min
  end

  def available_stock
    own = bulk_enabled? && stock.nil? ? Float::INFINITY : [(stock.to_i - stock_reserved.to_i), 0].max
    max = maximum_possible_stock
    return Float::INFINITY if own == Float::INFINITY && max == Float::INFINITY
    return max if own == Float::INFINITY
    return own if max == Float::INFINITY
    [own, max].min.to_i
  end

  def stock_display
    return "Unlimited" if available_stock == Float::INFINITY
    return "0" if available_stock <= 0
    available_stock.to_i.to_s
  end

  def out_of_stock?
    return false if bulk_enabled? && stock.nil?
    return false if available_stock == Float::INFINITY
    available_stock <= 0
  end

  def stock_warning_message
    max = maximum_possible_stock
    return nil if max == Float::INFINITY || max >= (stock || 0).to_i
    product_names = package_products.select { |pp| pp.available_stock == max }
                                   .map { |pp| pp.product.title }
                                   .join(', ')
    "Dear seller, you can only create up to #{max} packages because the following item(s) have limited stock: #{product_names}."
  end

  # ── NEW: Logistics helper methods (variant-aware) ──
  # These aggregate over each component in the package.
  def total_weight_kg
    package_products.sum { |pp| pp.effective_weight_kg }
  end

  def total_volume_cm3
    package_products.sum do |pp|
      l, w, h = pp.effective_dimensions
      (l.to_f * w.to_f * h.to_f)
    end
  end

  def refrigerated_needed?
    package_products.any? { |pp| pp.effective_refrigerated }
  end

  def fragile_needed?
    package_products.any? { |pp| pp.effective_fragile }
  end

  def logistics_details
    {
      weight_kg: total_weight_kg,
      volume_cm3: total_volume_cm3,
      refrigerated: refrigerated_needed?,
      fragile: fragile_needed?
    }
  end

  # ── Atomic stock reservation ──
  def reserve_stock!(quantity)
    raise ArgumentError, "quantity must be positive" if quantity <= 0

    Package.transaction do
      reload(lock: true)

      if !bulk_enabled? || !stock.nil?
        available = available_stock
        raise InsufficientStockError, "Not enough package stock for package #{id}" if available != Float::INFINITY && available < quantity
      end

      package_products.each do |pp|
        product = pp.product
        variant_attrs = pp.variant_attributes.presence
        product.with_lock do
          begin
            product.reserve_stock!(quantity, variant_attrs)
          rescue Product::InsufficientStockError => e
            raise InsufficientStockError, "Not enough stock for product #{product.id}: #{e.message}"
          end
        end
      end

      increment!(:stock_reserved, quantity) unless bulk_enabled? && stock.nil?
    end
    true
  end

  def release_stock!(quantity)
    raise ArgumentError, "quantity must be positive" if quantity.to_i <= 0

    Package.transaction do
      reload(lock: true)

      package_products.each do |pp|
        product = pp.product
        variant_attrs = pp.variant_attributes.presence
        product.with_lock do
          product.release_stock!(quantity, variant_attrs)
        end
      end

      decrement!(:stock_reserved, [stock_reserved, quantity].min) unless bulk_enabled? && stock.nil?
    end
    true
  end

  def restock!(quantity)
    raise ArgumentError, "quantity must be positive" if quantity.to_i <= 0

    Package.transaction do
      reload(lock: true)

      unless bulk_enabled? && stock.nil?
        decrement!(:stock_reserved, [stock_reserved, quantity].min)
        increment!(:stock, quantity.to_i)
      end

      package_products.each do |pp|
        product = pp.product
        next unless product
        variant_attrs = pp.variant_attributes.presence
        product.restock!(quantity.to_i, variant_attrs)
      end
    end
    true
  end

  # ── Discount & Price ──
  def apply_discount_to(base_price)
    return base_price if base_price.nil? || base_price <= 0
    return base_price if discount_value.blank? || discount_value.to_f <= 0
    case discount_type
    when 'percentage'
      (base_price * (1 - discount_value.to_f / 100.0)).round(2)
    when 'fixed'
      [base_price - discount_value.to_f, 0].max
    else
      base_price
    end
  end

  def current_price
    apply_discount_to(price)
  end

  def discount_percentage
    return 0 unless discount_value.present? && discount_value.to_f > 0
    case discount_type
    when 'percentage' then discount_value.to_i
    when 'fixed' then original_price.present? ? ((discount_value / original_price) * 100).round : 0
    else 0
    end
  end

  # ── Shipping ──
  def free_shipping?
    self[:free_shipping]
  end

  def free_delivery?
    free_shipping? || (seller_pays_shipping? && shipping_subsidy_type == 'full')
  end

  def seller_pays_shipping?
    self[:seller_pays_shipping] && shipping_subsidy_type.present?
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

  # ── Media helpers ──
  def image_urls
    @image_urls ||= begin
      urls = images.map { |img| Rails.application.routes.url_helpers.rails_blob_url(img, only_path: false) }
      if urls.empty?
        products_list = if package_products.loaded?
                          package_products.map(&:product).compact
                        else
                          products.includes(images_attachments: :blob).limit(4)
                        end
        urls = products_list.flat_map(&:image_urls).compact.uniq.first(4)
      end
      urls
    end
  end

  def video_urls
    @video_urls ||= videos.map { |v| Rails.application.routes.url_helpers.rails_blob_url(v, only_path: false) }
  end

  def items_count
    package_products.size
  end

  def vendor_display_badge
    vendor&.display_badge
  end

  # ── Smart trending score calculation ──
  def self.update_trending_scores!
    Package.find_each(batch_size: 500) do |package|
      product_scores = package.products.where.not(trending_score: nil).pluck(:trending_score)
      avg_product_score = product_scores.present? ? product_scores.sum / product_scores.size : 0.0

      engagement = package.reviews.size + package.items_count

      age_days = [(Time.current - package.created_at) / 1.day, 1].min
      age_decay = 1.0 / Math.sqrt(age_days)

      score = (avg_product_score * 0.6) + (engagement * 0.4)
      score *= age_decay

      package.update_column(:trending_score, score.round(4))
    end
  end

  # ── Search data ──
  def search_data
    {
      name: name,
      description: description,
      category_names: categories.pluck(:name).join(' '),
      category_ids: categories.pluck(:id),
      status: status,
      price: price,
      effective_price: current_price,
      original_price: original_price,
      discount_type: discount_type,
      discount_percentage: discount_percentage,
      items_count: package_products.size,
      vendor_id: vendor_id,
      vendor_status: vendor.status.to_s,
      delivery_label: delivery_label,
      free_delivery: free_delivery?,
      in_stock: !out_of_stock?,
      trending_score: trending_score,
      created_at: created_at
    }
  end

  private

  def reindex_with_rescue
    reindex(mode: :async)
  rescue Faraday::ConnectionFailed, Elasticsearch::Transport::Transport::Error => e
    Rails.logger.warn "Searchkick indexing skipped for Package #{id}: #{e.message}"
  end

  def stock_cannot_exceed_max_possible
    max = maximum_possible_stock
    return if max == Float::INFINITY
    if stock.present? && stock > max
      errors.add(:stock, "cannot exceed the available stock of the least available product (#{max}). #{stock_warning_message}")
    end
  end

  def compute_original_price
    if discount_value.present? && discount_value.to_f > 0 && price.present?
      case discount_type
      when 'percentage'
        if discount_value.to_f >= 100
          self.original_price = price
        else
          self.original_price = (price / (1 - discount_value.to_f / 100.0)).round(2)
        end
      when 'fixed'
        self.original_price = price + discount_value.to_f
      else
        self.original_price = nil
      end
    else
      self.original_price = nil
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
end