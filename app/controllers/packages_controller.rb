# app/controllers/packages_controller.rb

class PackagesController < ApplicationController
  skip_before_action :require_authentication, only: [:index, :show, :filter_options]
  before_action :require_seller!, only: [:create, :update, :destroy]
  before_action :set_package, only: [:update, :destroy]
  before_action :set_public_package, only: [:show]

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from Package::InsufficientStockError, with: :insufficient_stock

  # ---------- INDEX (public or seller) ----------
  def index
    if params[:vendor] == 'me'
      head :unauthorized and return unless authenticated?
      head :forbidden and return unless current_user.vendor

      base_scope = current_user.vendor.packages
                                .includes(package_associations)
                                .with_attached_images
                                .with_attached_videos

      packages = apply_package_filters(base_scope, params)
      packages = case params[:sort]
                 when 'price_asc'  then packages.order(price: :asc)
                 when 'price_desc' then packages.order(price: :desc)
                 when 'newest'     then packages.order(created_at: :desc)
                 else packages.order(trending_score: :desc, created_at: :desc)
                 end
    else
      packages = if params[:q].present?
                   begin
                     Package.search(params[:q],
                       where: search_where_clause(params),
                       order: sort_order(params),
                       includes: package_associations
                     ).records
                     .with_attached_images
                     .with_attached_videos
                   rescue Faraday::ConnectionFailed, Searchkick::Error => e
                     Rails.logger.warn "Elasticsearch unavailable for packages: #{e.message}"
                     Package.visible
                            .joins(vendor: :user)
                            .where(users: { status: :active })
                            .where("packages.name ILIKE ? OR packages.description ILIKE ?",
                                   "%#{params[:q]}%", "%#{params[:q]}%")
                            .includes(package_associations)
                            .with_attached_images
                            .with_attached_videos
                   end
                 else
                   base_scope = Package.visible
                                      .joins(vendor: :user)
                                      .where(users: { status: :active })
                                      .includes(package_associations)
                                      .with_attached_images
                                      .with_attached_videos
                   apply_package_filters(base_scope, params)
                 end

      unless params[:q].present?
        packages = case params[:sort]
                   when 'price_asc'  then packages.order(price: :asc)
                   when 'price_desc' then packages.order(price: :desc)
                   when 'newest'     then packages.order(created_at: :desc)
                   else packages.order(trending_score: :desc, created_at: :desc)
                   end
      end
    end

    page = (params[:page] || 1).to_i
    per_page = [(params[:per_page] || 20).to_i, 100].min
    total_count = packages.count(:id)
    packages = packages.limit(per_page).offset((page - 1) * per_page)

    render json: {
      data: packages.map { |pkg| package_json(pkg) },
      meta: {
        current_page: page,
        next_page: (page * per_page) < total_count ? page + 1 : nil,
        total_count: total_count,
        per_page: per_page
      }
    }
  end

  # ---------- SHOW (public) ----------
  def show
    unless @package.vendor&.accepting_orders? && @package.vendor&.user&.status == 'active'
      return render json: { error: 'Not found' }, status: :not_found
    end
    render json: package_json(@package)
  end

  # ---------- CREATE (seller) – transactional, stock capped, explicit package_products ----------
  def create
    unless current_user.vendor&.status == 'approved'
      return render json: { error: 'Your seller account is not yet approved.' }, status: :forbidden
    end

    Package.transaction do
      clean = sanitized_package_params
      clean[:status] = :active

      @package = current_user.vendor.packages.build(clean.except(:images, :videos, :category_ids, :products))
      authorize @package

      if params[:package][:category_ids].present?
        @package.categories = Category.where(id: params[:package][:category_ids])
      end

      product_entries = parse_product_entries(params[:package])
      unless product_entries.is_a?(Array) && product_entries.size >= 2
        render json: { error: "At least 2 products are required" }, status: :unprocessable_entity
        raise ActiveRecord::Rollback
      end

      product_ids = product_entries.map { |entry| entry[:product_id].to_i }.uniq
      vendor_products = current_user.vendor.products.where(id: product_ids)
      if vendor_products.count != product_ids.size
        render json: { error: "One or more products do not belong to you" }, status: :unprocessable_entity
        raise ActiveRecord::Rollback
      end

      # Build package_products (for validation) but we'll create explicitly after save
      product_entries.each do |entry|
        product = vendor_products.find { |p| p.id == entry[:product_id].to_i }
        next unless product
        @package.package_products.build(
          product: product,
          variant_attributes: entry[:variant_attributes] || {}
        )
      end

      # Stock cap logic considering stock_reserved = 0 at creation
      max_possible = @package.maximum_possible_stock
      if @package.stock.blank?
        @package.stock = nil if max_possible == Float::INFINITY
        @package.stock = max_possible unless max_possible == Float::INFINITY
      elsif max_possible != Float::INFINITY && @package.stock.to_i > max_possible
        @package.stock = max_possible
        @warning_message = @package.stock_warning_message
      end

      # Attach files
      if params[:package][:images].present?
        params[:package][:images].each { |img| @package.images.attach(img) if img.respond_to?(:read) }
      end
      if params[:package][:videos].present?
        params[:package][:videos].each { |vid| @package.videos.attach(vid) if vid.respond_to?(:read) }
      end

      # Save parent
      @package.save!

      # ★ Explicitly create package_products – ensures they are persisted
      product_entries.each do |entry|
        product = vendor_products.find { |p| p.id == entry[:product_id].to_i }
        next unless product

        # Check if already exists (from autosave)
        existing = @package.package_products.find_by(product_id: product.id, variant_attributes: entry[:variant_attributes] || {})
        next if existing

        @package.package_products.create!(
          product: product,
          variant_attributes: entry[:variant_attributes] || {}
        )
      end

      render json: package_json(@package).merge(
        warning: @warning_message
      ), status: :created
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: @package.errors.full_messages }, status: :unprocessable_entity
  rescue Searchkick::Error, Faraday::ConnectionFailed => e
    Rails.logger.error "Elasticsearch indexing failed for new package: #{e.message}"
    render json: package_json(@package), status: :created
  end

  # ---------- UPDATE (seller) – transactional, explicit package_products ----------
  def update
    authorize @package

    Package.transaction do
      clean = sanitized_package_params
      clean.delete(:status)

      if params[:package][:category_ids].present?
        @package.categories = Category.where(id: params[:package][:category_ids])
      end

      product_entries = parse_product_entries(params[:package])
      if product_entries.present?
        if product_entries.size < 2
          render json: { error: "At least 2 products are required" }, status: :unprocessable_entity
          raise ActiveRecord::Rollback
        end

        product_ids = product_entries.map { |entry| entry[:product_id].to_i }.uniq
        vendor_products = current_user.vendor.products.where(id: product_ids)
        if vendor_products.count != product_ids.size
          render json: { error: "One or more products do not belong to you" }, status: :unprocessable_entity
          raise ActiveRecord::Rollback
        end

        # Remove existing package_products (will recreate)
        @package.package_products.destroy_all
        product_entries.each do |entry|
          product = vendor_products.find { |p| p.id == entry[:product_id].to_i }
          next unless product
          @package.package_products.build(
            product: product,
            variant_attributes: entry[:variant_attributes] || {}
          )
        end
      end

      @package.assign_attributes(clean.except(:images, :videos, :category_ids, :products,
                                              :keep_image_ids, :keep_video_ids))

      # Stock cap logic considering existing stock_reserved
      max_possible = @package.maximum_possible_stock
      if @package.stock.blank?
        @package.stock = nil if max_possible == Float::INFINITY
        @package.stock = max_possible unless max_possible == Float::INFINITY
      elsif max_possible != Float::INFINITY
        available_after_update = @package.stock.to_i - @package.stock_reserved.to_i
        if available_after_update > max_possible
          @package.stock = max_possible + @package.stock_reserved.to_i
          @warning_message = @package.stock_warning_message
        end
      end

      # Attach / purge files
      if params[:package][:keep_image_ids].present?
        ids_to_keep = params[:package][:keep_image_ids].split(',').map(&:to_i).compact
        @package.images.where.not(id: ids_to_keep).each(&:purge)
      end
      if params[:package][:keep_video_ids].present?
        ids_to_keep = params[:package][:keep_video_ids].split(',').map(&:to_i).compact
        @package.videos.where.not(id: ids_to_keep).each(&:purge)
      end
      if params[:package][:images].present?
        params[:package][:images].each { |img| @package.images.attach(img) if img.respond_to?(:read) }
      end
      if params[:package][:videos].present?
        params[:package][:videos].each { |vid| @package.videos.attach(vid) if vid.respond_to?(:read) }
      end

      @package.save!

      # ★ Explicitly create package_products (if product_entries were provided)
      if product_entries.present?
        product_entries.each do |entry|
          product = current_user.vendor.products.find_by(id: entry[:product_id].to_i)
          next unless product

          existing = @package.package_products.find_by(product_id: product.id, variant_attributes: entry[:variant_attributes] || {})
          next if existing

          @package.package_products.create!(
            product: product,
            variant_attributes: entry[:variant_attributes] || {}
          )
        end
      end

      render json: package_json(@package).merge(
        warning: @warning_message
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: @package.errors.full_messages }, status: :unprocessable_entity
  rescue Searchkick::Error, Faraday::ConnectionFailed => e
    Rails.logger.error "Elasticsearch indexing failed for package #{@package.id}: #{e.message}"
    render json: package_json(@package)
  end

  # ---------- DESTROY ----------
  def destroy
    authorize @package

    if LineItem.where(package_id: @package.id).exists?
      return render json: { error: "This package cannot be deleted because it is part of existing orders." }, status: :unprocessable_entity
    end

    @package.images.each(&:purge)
    @package.videos.each(&:purge)

    @package.destroy!
    head :no_content
  rescue ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ---------- FILTER OPTIONS (public, cached) ----------
  def filter_options
    cache_key = "package_filter_options:#{params.to_json}"
    response = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      build_filter_options
    end
    render json: response
  rescue => e
    Rails.logger.error "package filter_options error: #{e.message}"
    render json: { categories: [], price_range: { min: 0, max: 10000 }, discount_types: [], brands: [] }
  end

  private

  def package_associations
    [
      :vendor,
      :categories,
      :reviews,
      package_products: {
        product: [
          :product_variants,
          images_attachments: :blob,
          videos_attachments: :blob
        ]
      }
    ]
  end

  def set_package
    @package = Package.includes(package_associations).find(params[:id])
  end

  def set_public_package
    @package = Package.where(status: :active)
                      .joins(:vendor)
                      .where(vendors: { status: :approved })
                      .includes(package_associations)
                      .find(params[:id])
  end

  def package_params
    params.require(:package).permit(
      :name, :description, :price, :stock, :featured,
      :discount_type, :discount_value, :discount_start, :discount_end,
      :original_price, :features,
      :shipping_type, :shipping_value,
      :seller_pays_shipping, :free_shipping, :shipping_subsidy_type, :shipping_subsidy_value,
      :keep_image_ids, :keep_video_ids,
      :status,
      :products,
      category_ids: [], images: [], videos: []
    )
  end

  def sanitized_package_params
    p = package_params.dup

    float_fields = %i[price original_price discount_value shipping_value shipping_subsidy_value]
    int_fields   = %i[stock]

    (float_fields + int_fields).each do |field|
      if p[field].is_a?(String)
        p[field] = p[field].strip.presence
        next unless p[field]
        if int_fields.include?(field)
          p[field] = p[field].to_i
        else
          p[field] = p[field].to_f
        end
      end
    end

    if p[:seller_pays_shipping].to_s == 'true'
      p[:seller_pays_shipping] = true
      p[:shipping_subsidy_type] ||= 'full'
    else
      p[:seller_pays_shipping] = false
      p[:shipping_subsidy_type] = nil
      p[:shipping_subsidy_value] = nil
    end

    p
  end

  def parse_product_entries(package_params)
    raw = package_params[:products]
    return [] if raw.blank?

    if raw.is_a?(String)
      begin
        parsed = JSON.parse(raw)
        parsed.is_a?(Array) ? parsed.map { |entry| entry.with_indifferent_access } : []
      rescue JSON::ParserError
        []
      end
    elsif raw.is_a?(Array)
      raw.map { |entry| entry.is_a?(Hash) ? entry.with_indifferent_access : {} }
    else
      []
    end
  end

  def search_where_clause(params)
    where = {}
    where[:status] = 'active'
    where[:vendor_status] = 'approved'
    where[:category_ids] = params[:category].split(',').map(&:to_i) if params[:category].present?
    if params[:price_min].present?
      where[:price] ||= {}
      where[:price][:gte] = params[:price_min].to_f
    end
    if params[:price_max].present?
      where[:price] ||= {}
      where[:price][:lte] = params[:price_max].to_f
    end
    where
  end

  def sort_order(params)
    case params[:sort]
    when 'price_asc'  then { price: :asc }
    when 'price_desc' then { price: :desc }
    when 'newest'     then { created_at: :desc }
    else { trending_score: :desc, created_at: :desc }
    end
  end

  def apply_package_filters(scope, params)
    scope = scope.joins(:categories).where(categories: { id: params[:category].to_s.split(',').map(&:to_i) }) if params[:category].present?
    scope = scope.joins(:vendor).where(vendors: { business_name: params[:brand].to_s.split(',').map(&:strip) }) if params[:brand].present?
    scope = scope.where('packages.price >= ?', params[:price_min].to_f) if params[:price_min].present?
    scope = scope.where('packages.price <= ?', params[:price_max].to_f) if params[:price_max].present?
    scope = scope.where(discount_type: params[:discount_type].to_s.split(',').map(&:strip)) if params[:discount_type].present?
    scope = scope.where(featured: true) if params[:featured] == 'true'
    scope
  end

  def build_filter_options
    packages = Package.visible

    category_ids = packages.joins(:categories).pluck('categories.id').uniq
    categories = Category.where(id: category_ids).select(:id, :name).map { |c| { id: c.id, name: c.name } }

    prices = packages.pluck(:price).compact
    price_min = prices.min || 0
    price_max = prices.max || 10000

    discount_types = packages.distinct.pluck(:discount_type).compact.uniq

    vendor_ids = packages.pluck(:vendor_id).compact.uniq
    vendors = Vendor.where(id: vendor_ids).map { |v| { id: v.id, name: v.business_name } }

    {
      categories: categories,
      price_range: { min: price_min, max: price_max },
      discount_types: discount_types,
      brands: vendors.map { |v| v[:name] }
    }
  end

  def serialize_stock(value)
    return nil if value == Float::INFINITY
    value.to_i
  end

  def package_json(package)
    pps = package.package_products

    reviews = package.reviews
    avg_rating = reviews.empty? ? 0.0 : (reviews.sum(&:rating).to_f / reviews.size).round(1)

    # Image fallback: use package's own images, otherwise first image from each product
    package_images = if package.images.attached?
                       package.images.map { |img| Rails.application.routes.url_helpers.rails_blob_url(img, only_path: false) }
                     else
                       []
                     end

    if package_images.empty?
      product_images = pps.flat_map do |pp|
        pr = pp.product
        next [] unless pr && pr.images.attached?
        pr.images.first(1).map { |img| Rails.application.routes.url_helpers.rails_blob_url(img, only_path: false) }
      end.compact.uniq
      package_images = product_images.first(3)
    end

    {
      id: package.id,
      name: package.name,
      description: package.description,
      price: package.current_price,
      formatted_price: ActiveSupport::NumberHelper.number_to_currency(
        package.current_price,
        unit: '', separator: '.', delimiter: ',', precision: 2
      ),
      original_price: package.original_price,
      discount_type: package.discount_type,
      discount_value: package.discount_value,
      discount_percentage: package.discount_percentage,
      rating: avg_rating,
      reviews_count: reviews.size,
      stock: package.stock,
      stock_display: package.stock_display,
      available_stock: serialize_stock(package.available_stock),
      max_possible_stock: serialize_stock(package.maximum_possible_stock),
      out_of_stock: package.out_of_stock?,
      stock_warning: package.stock_warning_message,
      free_shipping: package.free_shipping?,
      free_delivery: package.free_delivery?,
      delivery_label: package.delivery_label,
      seller_pays_shipping: package.seller_pays_shipping?,
      shipping_subsidy_type: package.shipping_subsidy_type,
      shipping_subsidy_value: package.shipping_subsidy_value,
      featured: package.featured,
      status: package.status,
      image_urls: package_images,
      video_urls: package.video_urls,
      items_count: package.items_count,
      features: package.features || [],
      trending_score: package.trending_score,
      vendor: {
        id: package.vendor.id,
        business_name: package.vendor.business_name,
        accepting_orders: package.vendor.accepting_orders,
        reopen_at: package.vendor.reopen_at,
        badge: package.vendor.display_badge,
        rating: package.vendor.average_rating,
        products_count: package.vendor.products_count,
        logo_url: package.vendor.logo_url,
        membership_tier: package.vendor.membership_tier,
        total_sales: package.vendor.total_sales_count,
        is_bulk_supplier: package.vendor.is_bulk_supplier,
        is_company: package.vendor.enterprise?,
        phone: package.vendor.phone
      },
      categories: package.categories.map { |c| { id: c.id, name: c.name } },
      products: pps.map do |pp|
        pr = pp.product
        next unless pr

        eff_price = pr.current_price.presence || pr.variants_data&.first&.dig('price')&.to_f

        {
          id: pr.id,
          title: pr.title,
          description: pr.description,
          price: pr.price,
          effective_price: eff_price,
          image_urls: pr.image_urls,
          video_urls: pr.video_urls,
          variant_attributes: pp.variant_attributes || {},
          available_stock: serialize_stock(pp.available_stock),
          stock: pr.stock,
          stock_display: pr.stock_display,
          bulk_enabled: pr.bulk_enabled?,
          weight_kg: pr.weight_kg,
          length_cm: pr.length_cm,
          width_cm: pr.width_cm,
          height_cm: pr.height_cm
        }
      end.compact
    }
  end

  def user_not_authorized
    render json: { error: 'You are not authorized to perform this action.' }, status: :forbidden
  end

  def insufficient_stock(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end
end