class Collection < ApplicationRecord
  has_one_attached :cover_image
  has_and_belongs_to_many :products

  validates :name, :slug, presence: true

  # ── Lifecycle callback for auto‑notification ──
  after_commit :broadcast_new_collection, on: :create

  # ── Safe URL generation ──
  def cover_image_url
    return nil unless cover_image.attached?

    host = ActiveStorage::Current.url_options&.dig(:host) || 'localhost'
    port = ActiveStorage::Current.url_options&.dig(:port) || 3000
    Rails.application.routes.url_helpers.rails_blob_url(
      cover_image, host: host, port: port, only_path: false
    )
  end

  # ── Auto‑refresh products based on criteria (only open, approved vendors) ──
  def refresh_products!
    return if auto_criteria.blank?

    scope = Product.joins(vendor: :user)
                   .where(products: { status: :active })
                   .where(users: { status: 'active' })
                   .where(vendors: { is_open: true, status: 'approved' })   # ← hides closed shops

    criteria = auto_criteria.is_a?(String) ? JSON.parse(auto_criteria) : auto_criteria
    return if criteria.blank?

    if criteria['category_ids'].present?
      cat_ids = Array(criteria['category_ids']).map(&:to_i).uniq
      scope = scope.where(category_id: cat_ids) if cat_ids.any?
    end

    scope = scope.where(is_flash_sale: true) if criteria['is_flash_sale']
    scope = scope.where(is_super_deal: true) if criteria['is_super_deal']

    if criteria['min_price'].present?
      min = criteria['min_price'].to_f
      scope = scope.where("COALESCE(products.price, (products.variants_data->0->>'price')::float) >= ?", min)
    end
    if criteria['max_price'].present?
      max = criteria['max_price'].to_f
      scope = scope.where("COALESCE(products.price, (products.variants_data->0->>'price')::float) <= ?", max)
    end

    limit = (criteria['limit'] || 20).to_i
    products_list = scope.order(created_at: :desc).limit(limit)

    self.product_ids = products_list.pluck(:id)
    save!
  end

  private

  # ── Broadcast a "new collection" notification to all users ──
  def broadcast_new_collection
    PromotionBroadcastJob.perform_later(:new_collection, {
      collection_id: id,
      collection_name: name,
      deep_link: "/collections/#{id}",
      image_url: cover_image_url,
      product_count: products.count
    })
  end
end