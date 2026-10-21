# app/controllers/api/v1/homepage_controller.rb
class Api::V1::HomepageController < ApplicationController
  allow_unauthenticated_access only: [:index, :collection]

  def index
    per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
    page = (params[:page] || 1).to_i.clamp(1, 10_000)

    cache_key = "homepage/v9/#{page}/#{per_page}/#{I18n.locale}"

    if (cached = Rails.cache.read(cache_key))
      return render json: cached, status: :ok
    end

    banners = []
    sections = []
    collections = []

    # ── Banners ──
    begin
      hero_banners = HeroBanner.active.map do |b|
        {
          id: b.id,
          title: b.title,
          subtitle: b.try(:subtitle),
          link: b.link,
          image_url: b.respond_to?(:image_url) ? b.image_url : (b.image.attached? ? url_for(b.image) : nil),
          display_order: b.display_order
        }
      end

      now = Time.current
      announcement_banners = AdminAnnouncement
        .where(announcement_type: 'banner', active: true)
        .where('start_date <= ? AND end_date >= ?', now, now)
        .order(:created_at)
        .map do |a|
          {
            id: a.id,
            title: a.title,
            subtitle: a.content.presence,
            link: a.link,
            image_url: a.image.attached? ? url_for(a.image) : nil,
            display_order: a.created_at.to_i
          }
        end

      banners = (hero_banners + announcement_banners).sort_by { |b| b[:display_order] }
    rescue => e
      Rails.logger.error "Homepage banners error: #{e.message}"
      banners = []
    end

    # ── Collections ──
    begin
      collections = Collection.where(is_active: true).order(:created_at).map do |c|
        product_scope = c.products
                         .merge(Product.visible)
                         .joins(vendor: :user)
                         .where(users: { status: :active })
                         .where(vendors: { status: :approved })
                         .includes(:vendor, :category, :product_variants,
                                   :images_attachments, :videos_attachments)

        top_products = product_scope.limit(4)

        {
          id: c.id,
          name: c.name,
          slug: c.slug,
          description: c.description,
          label: nil,
          cover_image_url: c.respond_to?(:cover_image_url) ? c.cover_image_url : (c.cover_image.attached? ? url_for(c.cover_image) : nil),
          product_count: product_scope.count,
          showcase_products: top_products.map { |p| product_summary(p) }
        }
      end
    rescue => e
      Rails.logger.error "Homepage collections error: #{e.message}"
      collections = []
    end

    # ── System‑driven product sections ──
    system_sections = [
      { type: 'new_arrivals',  title: 'New Arrivals' },
      { type: 'trending',      title: 'Trending' },
      { type: 'best_sellers',  title: 'Best Sellers' },
      { type: 'hot_deals',     title: 'Hot Deals' },
      { type: 'flash_sale',    title: 'Flash Sale' },
      { type: 'super_deal',    title: 'Super Deal' }
    ]

    system_sections.each do |sec|
      begin
        scope = Product.products_for_section(sec[:type])
                       .visible
                       .joins(vendor: :user)
                       .where(users: { status: :active })
                       .where(vendors: { status: :approved })
                       .includes(:vendor, :category, :product_variants,
                                 :images_attachments, :videos_attachments)

        products = scope.page(page).per(per_page)

        sections << {
          id: nil,
          name: sec[:title],
          section_type: sec[:type],
          display_order: system_sections.index(sec),
          products: products.map { |p| product_summary(p) },
          total_count: products.total_count,
          current_page: products.current_page,
          total_pages: products.total_pages,
          placeholder: products.empty? ? "No #{sec[:title].downcase} available right now" : nil
        }
      rescue => e
        Rails.logger.error "Homepage section #{sec[:title]} error: #{e.message}"
        sections << {
          id: nil,
          name: sec[:title],
          section_type: sec[:type],
          display_order: system_sections.index(sec),
          products: [],
          total_count: 0,
          current_page: 1,
          total_pages: 1,
          placeholder: "Temporarily unavailable"
        }
      end
    end

    # ★ UPDATED: Packages section – show all active visible packages, not only featured
    begin
      packages = Package.visible
                        .joins(vendor: :user)
                        .where(users: { status: :active })
                        .where(vendors: { status: :approved })
                        .where(status: :active)
                        .includes(:vendor, :categories,
                                  :images_attachments, :videos_attachments,
                                  :reviews,
                                  package_products: {
                                    product: [
                                      :vendor, :category, :product_variants,
                                      :images_attachments, :videos_attachments
                                    ]
                                  })
                        .order(created_at: :desc)
                        .limit(10)

      if packages.any?
        sections << {
          id: nil,
          name: 'Packages',
          section_type: 'packages',
          display_order: 98,
          packages: packages.map { |pkg| package_summary(pkg) },
          products: [],
          total_count: packages.size,
          current_page: 1,
          total_pages: 1,
          placeholder: nil
        }
      end
    rescue => e
      Rails.logger.error "Homepage packages error: #{e.message}"
    end

    # ── Featured Sellers ──
    begin
      featured_vendors = Vendor.where(status: :approved)
                               .joins(:user).where(users: { status: :active })
                               .where("(featured = true AND (featured_until IS NULL OR featured_until > ?))", Time.current)
                               .includes(:logo_attachment, :banner_attachment,
                                         products: [
                                           :vendor, :category, :product_variants,
                                           :images_attachments, :videos_attachments
                                         ])

      if featured_vendors.any?
        vendors_data = featured_vendors.map { |v| vendor_summary(v) }
        sections << {
          id: nil,
          name: 'Featured Sellers',
          section_type: 'featured_vendors',
          display_order: 99,
          vendors: vendors_data,
          products: [],
          total_count: vendors_data.size,
          current_page: 1,
          total_pages: 1,
          placeholder: nil
        }
      end
    rescue => e
      Rails.logger.error "Featured vendors error: #{e.message}"
    end

    # ── Sponsored Products section ──
    begin
      sponsored_products = Product.visible
                                  .where(sponsored: true)
                                  .joins(vendor: :user)
                                  .where(users: { status: :active })
                                  .where(vendors: { status: :approved })
                                  .includes(:vendor, :category, :product_variants,
                                            :images_attachments, :videos_attachments)
                                  .limit(10)

      if sponsored_products.any?
        sections << {
          id: nil,
          name: 'Sponsored',
          section_type: 'sponsored_products',
          display_order: 100,
          products: sponsored_products.map { |p| product_summary(p) },
          total_count: sponsored_products.size,
          current_page: 1,
          total_pages: 1,
          placeholder: nil
        }
      end
    rescue => e
      Rails.logger.error "Sponsored products error: #{e.message}"
    end

    response_data = {
      hero_banners: banners,
      promotional_sections: sections,
      collections: collections
    }

    Rails.cache.write(cache_key, response_data, expires_in: 60.seconds)

    render json: response_data, status: :ok
  end

  def collection
    page = (params[:page] || 1).to_i.clamp(1, 10_000)
    per_page = (params[:per_page] || 20).to_i.clamp(1, 100)

    cache_key = "homepage/v9/collection/#{params[:slug]}/#{page}/#{per_page}"

    if (cached = Rails.cache.read(cache_key))
      return render json: cached, status: :ok
    end

    collection = Collection.find_by(slug: params[:slug])

    if collection && collection.is_active?
      products = collection.products
                           .merge(Product.visible)
                           .joins(vendor: :user)
                           .where(users: { status: :active })
                           .where(vendors: { status: :approved })
                           .includes(:vendor, :category, :product_variants,
                                     :images_attachments, :videos_attachments)

      products_page = products.page(page).per(per_page)

      result = {
        id: collection.id,
        name: collection.name,
        slug: collection.slug,
        description: collection.description,
        label: collection.try(:label),
        cover_image_url: collection.respond_to?(:cover_image_url) ? collection.cover_image_url : (collection.cover_image.attached? ? url_for(collection.cover_image) : nil),
        product_count: products.size,
        products: products_page.map { |p| product_summary(p) },
        total_count: products_page.total_count,
        current_page: products_page.current_page,
        total_pages: products_page.total_pages
      }

      Rails.cache.write(cache_key, result, expires_in: 60.seconds)
      render json: result
    else
      render json: { error: "Collection not found" }, status: :not_found
    end
  end

  private

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

  # ── Product summary ──
  def product_summary(product)
    return {} if product.nil?

    base_price = product.price.to_f

    variant_prices = (product.variants_data || [])
      .map { |v| v.is_a?(Hash) ? v['price'].to_f : 0.0 }
      .select { |p| p > 0 }

    eff_price = if variant_prices.any?
                  variant_prices.map { |p| product.apply_discount_to(p) }.min
                elsif product.price.present? && product.price > 0
                  product.current_price
                else
                  base_price
                end
    eff_price = eff_price.presence&.to_f

    discount_pct = product.discount_percentage.to_i
    discount_pct = nil if discount_pct == 0

    original_price = product.original_price.to_f
    original_price = nil if original_price == 0.0

    flash_price = product.flash_sale_price.to_f
    flash_price = nil if flash_price == 0.0

    super_price = product.super_deal_price.to_f
    super_price = nil if super_price == 0.0

    vendor = product.vendor

    free_delivery = product.free_shipping? || (product.seller_pays_shipping? && product.shipping_subsidy_type == 'full')
    delivery_label = product.delivery_label

    enriched_variants = normalize_variant_attributes(product.variants_data || []).map do |v|
      next v unless v.is_a?(Hash) && v['price'].present?
      v.merge('effective_price' => product.apply_discount_to(v['price'].to_f))
    end

    {
      id: product.id,
      title: product.title,
      description: product.description,
      price: base_price,
      effective_price: eff_price,
      original_price: original_price,
      discount: discount_pct,
      rating: product.rating.to_f,
      reviews_count: product.reviews_count.to_i,
      sold_count: product.sold_count.to_i,
      stock: product.stock.to_i,
      free_shipping: product.free_shipping?,
      free_delivery: free_delivery,
      delivery_label: delivery_label,
      seller_pays_shipping: product.seller_pays_shipping?,
      shipping_subsidy_type: product.shipping_subsidy_type,
      shipping_subsidy_value: product.shipping_subsidy_value.to_f,
      is_flash_sale: product.is_flash_sale,
      flash_sale_price: flash_price,
      flash_sale_ends_at: product.flash_sale_ends_at,
      is_super_deal: product.is_super_deal,
      super_deal_price: super_price,
      super_deal_ends_at: product.super_deal_ends_at,
      is_trending: product.is_trending,
      is_hot_deal: product.is_hot_deal,
      sponsored: product.sponsored,
      featured: product.featured,
      views_count: product.views_count.to_i,
      image_urls: product.image_urls,
      video_urls: product.video_urls,
      category: product.category ? { id: product.category.id, name: product.category.name } : nil,
      vendor: vendor ? {
        id: vendor.id,
        business_name: vendor.business_name,
        accepting_orders: vendor.accepting_orders,
        reopen_at: vendor.reopen_at,
        rating: vendor.average_rating,
        products_count: vendor.products_count,
        logo_url: vendor.logo_url,
        membership_tier: vendor.membership_tier,
        total_sales: vendor.total_sales_count,
        badge: vendor.display_badge
      } : nil,
      product_attributes: product.product_attributes || {},
      variants: enriched_variants,
      variants_count: (product.variants_data || []).size,
      bulk_enabled: product.bulk_enabled,
      minimum_bulk_quantity: product.minimum_bulk_quantity,
      max_quantity_per_day: product.max_quantity_per_day,
      is_wholesale: product.bulk_enabled?
    }
  rescue => e
    Rails.logger.error "product_summary failed for product #{product&.id}: #{e.message}"
    {}
  end

  # ── Package summary ──
  def package_summary(package)
    return {} if package.nil?

    reviews = package.reviews.loaded? ? package.reviews : package.reviews
    avg_rating = reviews.empty? ? 0.0 : (reviews.sum(&:rating).to_f / reviews.size).round(1)

    products = package.package_products.map do |pp|
      product = pp.product
      next if product.nil?

      {
        id: product.id,
        title: product.title,
        price: product.price.to_f,
        effective_price: product.current_price,
        image_urls: product.image_urls,
        variant_attributes: pp.variant_attributes || {}
      }
    end.compact

    vendor = package.vendor

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
      stock_display: package.stock.nil? ? "Unlimited" : package.stock.to_s,
      available_stock: serialize_stock(package.available_stock),
      max_possible_stock: serialize_stock(package.maximum_possible_stock),
      out_of_stock: package.out_of_stock?,
      free_shipping: package.free_shipping?,
      free_delivery: package.free_delivery?,
      delivery_label: package.delivery_label,
      seller_pays_shipping: package.seller_pays_shipping?,
      shipping_subsidy_type: package.shipping_subsidy_type,
      shipping_subsidy_value: package.shipping_subsidy_value.to_f,
      featured: package.featured,
      status: package.status,
      image_urls: package.image_urls,
      video_urls: package.video_urls,
      items_count: package.items_count,
      vendor: vendor ? {
        id: vendor.id,
        business_name: vendor.business_name,
        accepting_orders: vendor.accepting_orders,
        reopen_at: vendor.reopen_at,
        rating: vendor.average_rating,
        products_count: vendor.products_count,
        logo_url: vendor.logo_url,
        membership_tier: vendor.membership_tier,
        total_sales: vendor.total_sales_count,
        badge: vendor.display_badge
      } : nil,
      categories: package.categories.map { |c| { id: c.id, name: c.name } },
      products: products
    }
  rescue => e
    Rails.logger.error "package_summary failed for package #{package&.id}: #{e.message}"
    {}
  end

  # ── Vendor summary for featured sellers section ──
  def vendor_summary(vendor)
    return {} if vendor.nil?

    best_product = vendor.products.visible.first rescue nil

    {
      id: vendor.id,
      business_name: vendor.business_name,
      description: vendor.description,
      logo_url: vendor.logo_url,
      banner_url: vendor.banner_url,
      rating: vendor.average_rating,
      total_sales: vendor.total_sales_count,
      products_count: vendor.products_count,
      membership_tier: vendor.membership_tier,
      badge: vendor.display_badge,
      is_company: vendor.enterprise?,
      is_bulk_supplier: vendor.is_bulk_supplier,
      is_verified: vendor.status == 'approved',
      featured_product: best_product ? product_summary(best_product) : nil
    }
  rescue => e
    Rails.logger.error "vendor_summary failed for vendor #{vendor&.id}: #{e.message}"
    {}
  end
end