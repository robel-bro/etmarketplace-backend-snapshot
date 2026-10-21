# app/models/promotional_section.rb
class PromotionalSection < ApplicationRecord
  has_many :promotional_section_products, dependent: :destroy
  has_many :products, through: :promotional_section_products

  validates :name, :slug, presence: true

  # ── Lifecycle callbacks for automated notifications ──
  after_commit :schedule_deal_activation, on: [:create, :update]

  # ── Helpers used by admin controller ──────────────
  def is_active?
    self[:is_active]
  end

  def system_generated?
    self[:system_generated] || false
  end

  # Replace stored products with a fresh automatic selection (no limit)
  def refresh_products!
    selected = fetch_products_by_type
    promotional_section_products.destroy_all
    selected.each do |product|
      promotional_section_products.create!(product: product)
    end
  end

  # ── Product selection logic (PUBLIC – used by API controller) ──
  def fetch_products_by_type
    base = Product.joins(vendor: :user)
                  .where(products: { status: :active })
                  .where(users: { status: 'active' })
                  .where(vendors: { status: 'approved' })   # shop open/closed no longer affects selection

    case section_type
    when 'flash_sale'
      base.where('rating >= ?', 3)
          .where('stock > 0 AND stock <= 10')
          .where('original_price > price')
          .order(Arel.sql('(original_price - price) DESC'))
          .order(views_count: :desc)
    when 'super_deal'
      base.where('rating >= ?', 3)
          .where('stock > 0 AND stock <= 5')
          .where('original_price > price')
          .order(Arel.sql('(original_price - price) DESC'))
          .order(views_count: :desc)
    when 'hot_deal'
      base.where('sold_count > 0')
          .where('stock > 0')
          .order(Arel.sql('(views_count * sold_count) / (stock + 1) DESC'))
    when 'trending'
      base.order(views_count: :desc)
    when 'best_sellers'
      base.order(sold_count: :desc)
    when 'new_arrivals'
      base.order(created_at: :desc)
    else
      Product.none
    end
  end

  private

  # ── Auto notification scheduling with rich metadata ──
  def schedule_deal_activation
    return unless is_active? && section_type.in?(%w[flash_sale super_deal hot_deal])

    # Get the first product's image for a magazine‑style notification
    hero_image = products.first&.first_image_url   # ⚡ lightweight helper

    metadata = {
      title: name,
      discount: discount_percentage || 0,
      deep_link: "/flash-deals",
      image_url: hero_image,
      section_type: section_type
    }

    if starts_at.blank? || starts_at <= Time.current
      PromotionBroadcastJob.perform_later(:flash_deal_started, metadata)
    else
      PromotionBroadcastJob.set(wait_until: starts_at).perform_later(:flash_deal_started, metadata)
    end
  end
end