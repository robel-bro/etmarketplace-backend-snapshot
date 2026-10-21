# app/controllers/products_controller.rb

class ProductsController < ApplicationController
  skip_before_action :require_authentication, only: [:index, :show, :similar, :filter_options, :featured]
  before_action :require_seller!, only: [:create, :update, :destroy]
  before_action :require_admin!, only: [:feature]
  before_action :set_product, only: [:show, :update, :destroy, :feature]

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from Product::InsufficientStockError, with: :insufficient_stock

  FORBIDDEN_FILTER_KEYS = %w[
    id vendor_id status price stock category_id created_at updated_at
    bulk_enabled minimum_bulk_quantity max_quantity_per_day variants_data
    product_attributes stock_reserved views_count sold_count rating
    is_flash_sale flash_sale_price flash_sale_ends_at is_super_deal
    super_deal_price super_deal_ends_at is_trending is_hot_deal
    free_shipping seller_pays_shipping shipping_subsidy_type
    shipping_subsidy_value discount_type discount_value original_price
    trending_score
  ].freeze

  # ---------- INDEX (public) ----------
  def index
    base_scope = if params[:vendor] == 'me'
                   head :unauthorized and return unless authenticated?
                   head :forbidden and return unless current_user.vendor
                   current_user.vendor.products
                              .includes(:vendor, :category, :product_variants, vendor: :membership_plan)
                              .includes(:images_attachments, :videos_attachments)
                              .left_joins(vendor: :membership_plan)
                 else
                   Product.visible
                          .joins(vendor: :user)
                          .where(users: { status: :active })
                          .where(vendors: { status: :approved })
                          .includes(:vendor, :category, :product_variants, vendor: [:user, :membership_plan])
                          .includes(:images_attachments, :videos_attachments)
                          .left_joins(vendor: :membership_plan)
                 end

    products = apply_product_filters(base_scope, params)

    # Dominant category for search results
    dominant_category_id = nil
    if params[:q].present? && params[:category].blank?
      category_counts = products.unscope(:order).group(:category_id).count(:id)
      dominant_entry = category_counts.max_by { |_id, count| count }
      dominant_category_id = dominant_entry&.first
    end

    # ── SORTING ──
    if params[:q].present? && (params[:sort].blank? || params[:sort] == 'relevance')
      tokens = params[:q].downcase.strip.split(/\s+/).reject(&:blank?)
      if tokens.any?
        score_parts = tokens.flat_map do |token|
          [
            similarity_coalesce('LOWER(products.title)', token),
            similarity_coalesce('LOWER(products.description)', token),
            similarity_coalesce('LOWER(categories.name)', token),
            similarity_coalesce("LOWER(products.product_attributes->>'brand')", token),
            similarity_coalesce('products.product_attributes::text', token)
          ]
        end
        sum_expr = score_parts.reduce { |sum, part| Arel::Nodes::Addition.new(sum, part) }
        products = products.order(Arel::Nodes::Descending.new(sum_expr))
                           .order(Arel.sql('COALESCE(membership_plans.price, 0) DESC'))
      end
    else
      case params[:sort]
      when 'price_asc'
        products = products.order(
          Arel.sql("COALESCE(products.price, (SELECT MIN((v->>'price')::float) FROM jsonb_array_elements(products.variants_data) v)) ASC")
        )
      when 'price_desc'
        products = products.order(
          Arel.sql("COALESCE(products.price, (SELECT MAX((v->>'price')::float) FROM jsonb_array_elements(products.variants_data) v)) DESC")
        )
      when 'newest'     then products = products.order(created_at: :desc)
      when 'trending'   then products = products.order(trending_score: :desc, views_count: :desc, sold_count: :desc, rating: :desc)
      when 'best_sellers' then products = products.order(sold_count: :desc)
      when 'rating'     then products = products.order(rating: :desc)
      else
        products = products.order(trending_score: :desc, views_count: :desc, sold_count: :desc, rating: :desc)
                           .order(Arel.sql('COALESCE(membership_plans.price, 0) DESC'))
      end
    end

    page = (params[:page] || 1).to_i
    per_page = if params[:vendor] == 'me'
                 100
               else
                 [(params[:per_page] || params[:limit] || 20).to_i, 100].min
               end

    total_count = products.count(:id)
    products = products.limit(per_page).offset((page - 1) * per_page)

    product_ids = products.pluck(:id)
    sold_map = params[:vendor] != 'me' ? Product.today_quantity_sold_map(product_ids) : {}

    dominant_name = Category.find_by(id: dominant_category_id)&.name if dominant_category_id

    render json: {
      data: products.map { |p| product_json(p, sold_map: sold_map) },
      meta: {
        current_page: page,
        next_page: (page * per_page) < total_count ? page + 1 : nil,
        total_count: total_count,
        per_page: per_page,
        dominant_category: dominant_category_id ? { id: dominant_category_id, name: dominant_name } : nil
      }
    }
  end

  # ---------- SHOW (public) ----------
  def show
    @product = Product.includes(:product_variants, vendor: :membership_plan).find(params[:id])
    unless @product.status == 'active' &&
           @product.vendor&.status == 'approved' &&
           @product.vendor&.user&.status == 'active'
      unless current_user&.admin? || (current_user&.vendor == @product.vendor)
        return render json: { error: 'Not found' }, status: :not_found
      end
    end

    @product.increment!(:views_count)
    sold_map = Product.today_quantity_sold_map([@product.id])
    render json: product_json(@product, sold_map: sold_map)
  end

  # ---------- SIMILAR (public) – same category/subtree, smart sorted ----------
  def similar
    product = Product.visible.find(params[:id])
    category_ids = product.category&.subtree_ids || [product.category_id].compact
    similar_products = Product.visible
                              .where(category_id: category_ids)
                              .where.not(id: product.id)
                              .smart_sort
                              .limit(12)
    product_ids = similar_products.pluck(:id)
    sold_map = Product.today_quantity_sold_map(product_ids)
    render json: similar_products.map { |p| product_json(p, sold_map: sold_map) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  # ---------- CREATE (seller) – active by default ----------
  def create
    unless current_user.vendor&.status == 'approved'
      return render json: { error: 'Your seller account is not yet approved.' }, status: :forbidden
    end

    membership_settings = Setting.get('membership') || {}
    if membership_settings['sellerMembershipRequired'] && !current_user.vendor.membership_active?
      return render json: { error: "An active membership plan is required to list products." }, status: :forbidden
    end

    unless Category.exists?(id: product_params[:category_id])
      return render json: { errors: ['Category not found'] }, status: :unprocessable_entity
    end

    build_params = product_params.except(:images, :videos, :product_attributes, :variants, :clear_stock)
                                 .merge(status: :active)

    @product = current_user.vendor.products.build(build_params)

    # Attach files
    if params[:product][:images].present?
      params[:product][:images].each { |img| @product.images.attach(img) if img.respond_to?(:read) }
    end
    if params[:product][:videos].present?
      params[:product][:videos].each { |vid| @product.videos.attach(vid) if vid.respond_to?(:read) }
    end

    # Bulk stock handling
    if @product.bulk_enabled? && product_params[:stock].blank?
      @product.stock = nil
    end

    # Handle both String and Hash/Array
    if params[:product][:product_attributes].present?
      @product.product_attributes = extract_product_attributes(params[:product][:product_attributes])
    end

    if params[:product][:variants].present?
      @product.variants_data = extract_and_normalize_variants(params[:product][:variants])
    end

    authorize @product
    @product.save!

    render json: product_json(@product), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
  rescue Searchkick::Error => e
    Rails.logger.error "Searchkick indexing failed for new product: #{e.message}"
    render json: product_json(@product), status: :created
  end

  # ---------- UPDATE (seller) – hardened ----------
  def update
    authorize @product

    # Image/video management
    keep_ids = params.dig(:product, :keep_image_ids)
    if keep_ids.present?
      ids_to_keep = keep_ids.split(',').map(&:to_i).compact
      @product.images.where.not(id: ids_to_keep).each(&:purge)
    end
    keep_video_ids = params.dig(:product, :keep_video_ids)
    if keep_video_ids.present?
      ids_to_keep = keep_video_ids.split(',').map(&:to_i).compact
      @product.videos.where.not(id: ids_to_keep).each(&:purge)
    end

    if params[:product][:images].present?
      params[:product][:images].each { |img| @product.images.attach(img) if img.respond_to?(:read) }
    end
    if params[:product][:videos].present?
      params[:product][:videos].each { |vid| @product.videos.attach(vid) if vid.respond_to?(:read) }
    end

    if params[:product][:product_attributes].present?
      @product.product_attributes = extract_product_attributes(params[:product][:product_attributes])
    end

    if params[:product][:variants].present?
      @product.variants_data = extract_and_normalize_variants(params[:product][:variants])
    end

    attrs = product_params.except(:images, :videos, :product_attributes, :variants,
                                  :keep_image_ids, :keep_video_ids, :status, :vendor_id, :clear_stock)

    # Bulk stock handling: allow explicit clearing via clear_stock param
    if params[:product][:clear_stock] == 'true' || params[:product][:clear_stock] == true
      @product.stock = nil
    elsif @product.bulk_enabled? && product_params[:stock].blank?
      @product.stock = nil
    end

    @product.assign_attributes(attrs)
    @product.save!

    render json: product_json(@product)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
  rescue Searchkick::Error => e
    Rails.logger.error "Searchkick indexing failed for product #{@product.id}: #{e.message}"
    render json: product_json(@product)
  end

  # ---------- DESTROY ----------
  def destroy
    authorize @product

    if @product.line_items.exists?
      return render json: { error: "This product cannot be deleted because it is part of existing orders." }, status: :unprocessable_entity
    end

    CartItem.where(product_id: @product.id).destroy_all
    WishlistItem.where(product_id: @product.id).destroy_all
    PackageProduct.where(product_id: @product.id).destroy_all
    Reservation.where(product_id: @product.id).destroy_all

    @product.images.each(&:purge)
    @product.videos.each(&:purge)

    @product.destroy!
    head :no_content
  rescue ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::InvalidForeignKey => e
    render json: { error: "This product cannot be deleted because it is part of existing orders or packages." }, status: :unprocessable_entity
  end

  # ---------- FEATURE (admin only) ----------
  def feature
    authorize @product, :feature?
    if @product.update(featured: !@product.featured)
      render json: product_json(@product)
    else
      render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # ---------- FEATURED (public) ----------
  def featured
    products = Product.visible
                      .where(featured: true, status: :active)
                      .joins(vendor: :user).where(users: { status: :active })
                      .includes(:product_variants, vendor: :membership_plan)
                      .limit(20)
    product_ids = products.pluck(:id)
    sold_map = Product.today_quantity_sold_map(product_ids)
    render json: products.map { |p| product_json(p, sold_map: sold_map) }
  end

  # ---------- FILTER OPTIONS (public, cached) ----------
  def filter_options
    cache_key = "filter_options:#{params.to_json}"
    response = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      build_filter_options
    end
    render json: response
  rescue => e
    Rails.logger.error "filter_options error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    fallback_cats = Category.roots.map { |cat| { id: cat.id, name: cat.name, count: 0, image_url: nil } }
    render json: {
      brands: [],
      attributes: {},
      categories: fallback_cats,
      price_range: { min: 0, max: 10000 },
      ratings: [],
      delivery_options: []
    }
  end

  private

  def extract_product_attributes(value)
    if value.is_a?(String)
      parsed = safe_parse_json(value)
      parsed.is_a?(Hash) ? parsed : {}
    elsif value.is_a?(Hash)
      value
    else
      {}
    end
  end

  def extract_and_normalize_variants(value)
    raw = if value.is_a?(String)
            safe_parse_json(value)
          elsif value.is_a?(Array)
            value
          else
            []
          end
    normalize_variants(raw)
  end

  def build_filter_options
    products = Product.visible
                      .joins(vendor: :user).where(users: { status: 'active' })
                      .where(vendors: { status: :approved })
                      .includes(:product_variants)

    if params[:is_flash_sale] == 'true'
      products = products.where(is_flash_sale: true)
                         .where('flash_sale_ends_at > ?', Time.current)
    end
    if params[:is_super_deal] == 'true'
      products = products.where(is_super_deal: true)
                         .where('super_deal_ends_at > ?', Time.current)
    end
    if params[:is_hot_deal] == 'true'
      products = products.where('sold_count > 0 AND stock > 0')
    end

    if params[:category].present?
      cat = Category.find_by(id: params[:category].to_i)
      products = products.where(category_id: cat.subtree_ids) if cat
    elsif params[:parent_category].present?
      parent = Category.find_by(id: params[:parent_category].to_i)
      products = products.where(category_id: parent.subtree_ids) if parent
    end

    scope = products

    # ---- Brands ----
    brand_counts = scope
      .where.not("products.product_attributes->>'brand' IS NULL")
      .where.not("products.product_attributes->>'brand' = ''")
      .group(Arel.sql("LOWER(products.product_attributes->>'brand')"))
      .count
    brands = brand_counts.reject { |k, _| k.nil? }
                         .map { |k, v| { name: k, count: v } }
                         .sort_by { |b| b[:name] }

    # ---- Dynamic attributes ----
    keys = scope.where.not(products: { product_attributes: nil })
                .pluck(Arel.sql("jsonb_object_keys(products.product_attributes)"))
                .flatten.uniq
    dynamic_attrs = {}
    keys.each do |key|
      next if key == 'brand'
      vals = scope.where.not(products: { product_attributes: nil })
                  .group(Arel.sql("LOWER(products.product_attributes->>'#{key}')"))
                  .count
                  .reject { |k, _| k.nil? }
      next if vals.empty?
      normalized = vals.map { |v, cnt| { value: v, count: cnt } }
                       .sort_by { |e| e[:value] }
      dynamic_attrs[key] = normalized
    end

    # ---- Categories ----
    if params[:parent_category].present?
      parent = Category.find_by(id: params[:parent_category].to_i)
      if parent
        child_ids = parent.children.where(id: scope.distinct.pluck('products.category_id')).pluck(:id)
        categories = Category.where(id: child_ids).includes(:image_attachment).map do |cat|
          cnt = scope.where(category_id: cat.subtree_ids).count
          { id: cat.id, name: cat.name, count: cnt,
            image_url: cat.image.attached? ? Rails.application.routes.url_helpers.rails_blob_url(cat.image, only_path: false) : nil }
        end
      else
        categories = []
      end
    elsif params[:category].present?
      cat = Category.find_by(id: params[:category].to_i)
      if cat
        children = cat.children.where(id: scope.distinct.pluck('products.category_id'))
        categories = children.includes(:image_attachment).map do |c|
          cnt = scope.where(category_id: c.subtree_ids).count
          { id: c.id, name: c.name, count: cnt,
            image_url: c.image.attached? ? Rails.application.routes.url_helpers.rails_blob_url(c.image, only_path: false) : nil }
        end
      else
        categories = []
      end
    else
      leaf_ids = scope.distinct.pluck('products.category_id').compact.uniq
      if leaf_ids.any?
        top_level_ids = Category.where(id: leaf_ids).map(&:root).map(&:id).uniq
        categories = Category.where(id: top_level_ids).includes(:image_attachment).map do |cat|
          cnt = scope.where(category_id: cat.subtree_ids).count
          { id: cat.id, name: cat.name, count: cnt,
            image_url: cat.image.attached? ? Rails.application.routes.url_helpers.rails_blob_url(cat.image, only_path: false) : nil }
        end
      else
        categories = Category.roots.includes(:image_attachment).map do |cat|
          { id: cat.id, name: cat.name, count: 0,
            image_url: cat.image.attached? ? Rails.application.routes.url_helpers.rails_blob_url(cat.image, only_path: false) : nil }
        end
      end
    end

    # ---- Price range ----
    prices = scope.pluck(Arel.sql("COALESCE(products.price, (products.variants_data->0->>'price')::float)")).compact
    price_min = prices.min || 0
    price_max = prices.max || 10000

    # ---- Ratings ----
    rating_counts = scope.where.not(rating: nil).group('products.rating').count
    ratings = rating_counts.reject { |k, _| k.nil? }
                           .map { |r, cnt| { value: r, count: cnt } }
                           .sort_by { |e| -e[:value] }

    # ---- Delivery options ----
    delivery_labels_sql = <<-SQL.squish
      CASE
        WHEN products.free_shipping = true THEN 'Free Shipping'
        WHEN products.seller_pays_shipping = true AND products.shipping_subsidy_type = 'percent'
          THEN CONCAT(COALESCE(products.shipping_subsidy_value, 0)::int, '% Off Shipping')
        WHEN products.seller_pays_shipping = true AND products.shipping_subsidy_type = 'fixed'
          THEN CONCAT('ETB ', COALESCE(products.shipping_subsidy_value, 0), ' Off Shipping')
        WHEN products.seller_pays_shipping = true AND products.shipping_subsidy_type IS NOT NULL
          THEN 'Discounted Shipping'
        ELSE 'Paid Shipping'
      END
    SQL

    delivery_counts = scope.group(Arel.sql(delivery_labels_sql)).count
                           .reject { |k, _| k.nil? }
    delivery_options = delivery_counts.map { |label, cnt| { label: label, count: cnt } }
                                      .sort_by { |d| d[:label] }

    {
      brands: brands,
      attributes: dynamic_attrs,
      categories: categories,
      price_range: { min: price_min, max: price_max },
      ratings: ratings,
      delivery_options: delivery_options
    }
  end

  def similarity_coalesce(column_expr, token)
    Arel::Nodes::NamedFunction.new('COALESCE', [
      Arel::Nodes::NamedFunction.new('similarity', [Arel.sql(column_expr), Arel::Nodes.build_quoted(token)]),
      0
    ])
  end

  def apply_product_filters(products, params)
    if params[:q].present?
      query = params[:q].downcase.strip
      tokens = query.split(/\s+/).reject(&:blank?)

      if tokens.any?
        best_category_ids = tokens.map do |token|
          best_cat = Category.select("categories.*, word_similarity(#{ActiveRecord::Base.connection.quote(token)}, LOWER(categories.name)) AS sim_score")
                             .where("word_similarity(?, LOWER(categories.name)) > 0.45", token)
                             .order('sim_score DESC')
                             .limit(1)
                             .first
          best_cat ? best_cat.subtree_ids : []
        end

        all_matched = best_category_ids.all? { |ids| ids.any? }
        common_ids = if all_matched
                       best_category_ids.reduce(:&)
                     else
                       []
                     end

        conditions = []
        query_params = []

        if common_ids.any?
          conditions << "products.category_id IN (?)"
          query_params << common_ids
        else
          token_clauses = tokens.map do |token|
            th = token.length <= 3 ? 0.55 : 0.4
            "(word_similarity(?, LOWER(products.title)) > #{th} OR " \
            "word_similarity(?, LOWER(products.description)) > #{th} OR " \
            "word_similarity(?, LOWER(categories.name)) > #{th} OR " \
            "word_similarity(?, LOWER(products.product_attributes->>'brand')) > #{th} OR " \
            "word_similarity(?, products.product_attributes::text) > #{th})"
          end
          conditions << "(#{token_clauses.join(' AND ')})"
          tokens.each { |t| query_params.concat([t] * 5) }
        end

        products = products.left_joins(:category)
                           .where(conditions.join(' OR '), *query_params)
      end
    end

    if params[:is_flash_sale].present? && params[:is_flash_sale] == 'true'
      products = products.where(is_flash_sale: true)
                         .where('flash_sale_ends_at > ?', Time.current)
    end
    if params[:is_super_deal].present? && params[:is_super_deal] == 'true'
      products = products.where(is_super_deal: true)
                         .where('super_deal_ends_at > ?', Time.current)
    end
    if params[:is_hot_deal].present? && params[:is_hot_deal] == 'true'
      products = products.where('sold_count > 0 AND stock > 0')
    end

    if params[:category].present?
      cat_ids = if params[:category].is_a?(Array)
                  params[:category].map(&:to_i)
                else
                  params[:category].to_s.split(',').map(&:to_i)
                end
      cat_ids.uniq!
      descendant_ids = []
      cat_ids.each do |cat_id|
        cat = Category.find_by(id: cat_id)
        descendant_ids.concat(cat.subtree_ids) if cat
      end
      descendant_ids.uniq!
      products = products.where(category_id: descendant_ids) if descendant_ids.any?
    end

    if params[:price_min].present? && params[:price_min].to_f > 0
      products = products.where("COALESCE(products.price, (products.variants_data->0->>'price')::float) >= ?", params[:price_min].to_f)
    end
    if params[:price_max].present? && params[:price_max].to_f > 0
      products = products.where("COALESCE(products.price, (products.variants_data->0->>'price')::float) <= ?", params[:price_max].to_f)
    end

    if params[:rating].present?
      ratings = if params[:rating].is_a?(Array)
                  params[:rating].map(&:to_f)
                else
                  params[:rating].to_s.split(',').map(&:to_f)
                end
      ratings.reject! { |r| r <= 0 }
      if ratings.any?
        min_rating = ratings.min
        products = products.where('products.rating >= ?', min_rating)
      end
    end

    if params[:delivery].present?
      delivery_labels = if params[:delivery].is_a?(Array)
                          params[:delivery]
                        else
                          params[:delivery].to_s.split(',')
                        end
      delivery_labels.reject!(&:blank?)
      if delivery_labels.any?
        delivery_case_sql = <<-SQL.squish
          CASE
            WHEN products.free_shipping = true THEN 'Free Shipping'
            WHEN products.seller_pays_shipping = true AND products.shipping_subsidy_type = 'percent'
              THEN CONCAT(COALESCE(products.shipping_subsidy_value, 0)::int, '% Off Shipping')
            WHEN products.seller_pays_shipping = true AND products.shipping_subsidy_type = 'fixed'
              THEN CONCAT('ETB ', COALESCE(products.shipping_subsidy_value, 0), ' Off Shipping')
            WHEN products.seller_pays_shipping = true AND products.shipping_subsidy_type IS NOT NULL
              THEN 'Discounted Shipping'
            ELSE 'Paid Shipping'
          END
        SQL

        products = products.where(
          "#{delivery_case_sql} IN (:labels)", labels: delivery_labels
        )
      end
    end

    if params[:brand].present?
      brand_names = if params[:brand].is_a?(Array)
                      params[:brand].map(&:to_s)
                    else
                      params[:brand].to_s.split(',').map(&:strip)
                    end
      brand_names.reject!(&:blank?)
      if brand_names.any?
        products = products.where("LOWER(products.product_attributes->>'brand') IN (?)", brand_names.map(&:downcase))
      end
    end

    known_params = %w[controller action vendor category price_min price_max featured sort limit offset page per_page is_flash_sale is_super_deal is_hot_deal q brand rating free_shipping delivery parent_category _t]

    params.each do |key, value|
      next if known_params.include?(key) || !value.present?
      next unless key.match?(/\A[a-zA-Z0-9_]+\z/)
      next if FORBIDDEN_FILTER_KEYS.include?(key)

      values = if value.is_a?(Array)
                 value.map(&:to_s)
               else
                 value.split(',')
               end
      values = values.map(&:downcase).reject(&:blank?)
      products = products.where("LOWER(products.product_attributes->>'#{key}') IN (?)", values) if values.any?
    end

    products
  end

  def set_product
    @product = Product.includes(:product_variants, vendor: :membership_plan).find(params[:id])
  end

  def product_params
    params.require(:product).permit(
      :title, :description, :price, :original_price, :discount, :discount_type, :discount_value,
      :stock, :category_id, :product_attributes, :variants,
      :seller_pays_shipping, :free_shipping, :shipping_subsidy_type, :shipping_subsidy_value,
      :bulk_enabled, :minimum_bulk_quantity, :max_quantity_per_day,
      :weight_kg, :length_cm, :width_cm, :height_cm,
      :keep_image_ids, :keep_video_ids, :clear_stock,
      images: [], videos: []
    ).tap do |whitelisted|
      whitelisted.delete(:vendor_id)
      whitelisted.delete(:status)
    end
  end

  def safe_parse_json(str)
    JSON.parse(str)
  rescue JSON::ParserError
    nil
  end

  def normalize_variants(variants)
    return [] unless variants.is_a?(Array)
    variants.map do |v|
      v = v.dup
      v['price'] = v['price'].to_f if v['price'].present?
      stock_val = v['stock']
      if stock_val.blank? || stock_val.to_s.strip == ''
        v['stock'] = '0'
      else
        v['stock'] = stock_val.to_i.to_s
      end
      v
    end
  end

  def normalize_variant_attributes(variants)
    return variants unless variants.is_a?(Array)
    all_keys = variants.flat_map { |v| v['attributes']&.keys || [] }.uniq
    variants.each do |v|
      next unless v.is_a?(Hash)
      attrs = v['attributes'] || {}
      all_keys.each { |k| attrs[k] ||= "" }
      v['attributes'] = attrs
    end
    variants
  end

  def serialize_stock(value)
    return nil if value == Float::INFINITY
    value.to_i
  end

  def product_json(product, sold_map: {})
    variant_prices = (product.variants_data || [])
      .map { |v| v.is_a?(Hash) ? v['price'].to_f : 0.0 }
      .select { |p| p > 0 }

    has_variants = product.has_variants?

    effective = if has_variants && variant_prices.any?
                  variant_prices.map { |p| product.effective_price_for(p) }.min
                elsif product.price.present? && product.price > 0
                  product.current_price
                else
                  0.0
                end

    stock_display = product.stock_display

    vendor_data = if product.vendor
                    {
                      id: product.vendor.id,
                      business_name: product.vendor.business_name,
                      accepting_orders: product.vendor.accepting_orders?,
                      reopen_at: product.vendor.reopen_at,
                      rating: product.vendor.average_rating,
                      products_count: product.vendor.products_count,
                      logo_url: product.vendor.logo_url,
                      membership_tier: product.vendor.membership_tier,
                      total_sales: product.vendor.total_sales_count,
                      badge: product.vendor.display_badge,
                      is_bulk_supplier: product.vendor.is_bulk_supplier,
                      is_company: product.vendor.enterprise?
                    }
                  else
                    nil
                  end

    sold = sold_map[product.id] || 0
    remaining = product.remaining_daily_quantity
    orderable = product.can_be_ordered?(1, preloaded_sold: sold)
    reason = product.unavailable_reason(preloaded_sold: sold)

    enriched_variants = normalize_variant_attributes(product.variants_data || []).map do |v|
      next v unless v.is_a?(Hash) && v['price'].present?
      v.merge('effective_price' => product.effective_price_for(v['price'].to_f))
    end

    free_delivery = product.free_delivery?

    {
      id: product.id,
      title: product.title,
      description: product.description,
      price: product.price,
      effective_price: effective,
      original_price: product.original_price,
      discount_type: product.discount_type,
      discount_value: product.discount_value,
      discount: product.discount_percentage,
      rating: product.rating,
      reviews_count: product.reviews_count,
      sold_count: product.sold_count,
      free_shipping: product.free_shipping,
      free_delivery: free_delivery,
      delivery_label: product.delivery_label,
      stock: product.stock,
      available_stock: serialize_stock(product.available_stock),
      stock_display: stock_display,
      has_variants: has_variants,
      status: product.status,
      featured: product.featured,
      sponsored: product.sponsored,
      views_count: product.views_count,
      trending_score: product.trending_score,
      is_flash_sale: product.is_flash_sale,
      flash_sale_price: product.flash_sale_price,
      flash_sale_ends_at: product.flash_sale_ends_at,
      is_super_deal: product.is_super_deal,
      super_deal_price: product.super_deal_price,
      super_deal_ends_at: product.super_deal_ends_at,
      is_trending: product.is_trending,
      is_hot_deal: product.is_hot_deal,
      category: product.category ? { id: product.category.id, name: product.category.name } : nil,
      vendor: vendor_data,
      image_urls: product.image_urls,
      image_ids: product.images.map(&:id),
      video_urls: product.video_urls,
      product_attributes: product.product_attributes || {},
      variants: enriched_variants,
      views: product.views_count,
      sales: product.sold_count,
      variants_count: product.variants_count,
      seller_pays_shipping: product.seller_pays_shipping,
      shipping_subsidy_type: product.shipping_subsidy_type,
      shipping_subsidy_value: product.shipping_subsidy_value,
      bulk_enabled: product.bulk_enabled,
      minimum_bulk_quantity: product.minimum_bulk_quantity,
      max_quantity_per_day: product.max_quantity_per_day,
      remaining_daily_quantity: remaining,
      orderable: orderable,
      unavailable_reason: reason,
      out_of_stock: product.out_of_stock?,
      weight_kg: product.weight_kg,
      length_cm: product.length_cm,
      width_cm: product.width_cm,
      height_cm: product.height_cm
    }
  end

  def user_not_authorized
    render json: { error: 'You are not authorized to perform this action.' }, status: :forbidden
  end

  def insufficient_stock(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end
end