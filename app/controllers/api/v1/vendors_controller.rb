class Api::V1::VendorsController < ApplicationController
  allow_unauthenticated_access only: [:index, :show, :filter_options]

  # GET /api/v1/vendors
  def index
    vendors = Vendor.approved

    vendors = vendors.bulk_suppliers if params[:bulk].to_s == 'true'

    vendors = vendors.includes(:products, :packages)

    if params[:search].present?
      vendors = vendors.where("business_name ILIKE ?", "%#{params[:search]}%")
    end

    if params[:category].present?
      vendors = vendors.joins(products: :category)
                       .where(categories: { id: params[:category] })
                       .distinct
    end

    if params[:min_rating].present?
      vendors = vendors.to_a.select { |v| v.average_rating >= params[:min_rating].to_f }
    else
      vendors = vendors.to_a
    end

    render json: vendors.map { |v| vendor_summary_json(v) }
  end

  # GET /api/v1/vendors/:id
  def show
    vendor = Vendor.approved.find(params[:id])
    render json: vendor_detail_json(vendor)
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Shop not found" }, status: :not_found
  end

  # ★ Section‑aware filter options
  # GET /api/v1/vendors/:id/filter_options
  def filter_options
    vendor = Vendor.approved.find(params[:id])
    products = vendor.products.active
    packages = vendor.packages

    # ── Delivery label SQL (now matches Product#delivery_label) ──
    delivery_label_sql = <<-SQL.squish
      CASE
        WHEN free_shipping = true THEN 'Free Shipping'
        WHEN seller_pays_shipping = true AND shipping_subsidy_type = 'percent'
          THEN CONCAT(COALESCE(shipping_subsidy_value, 0)::int, '% Off Shipping')
        WHEN seller_pays_shipping = true AND shipping_subsidy_type = 'fixed'
          THEN CONCAT('$', COALESCE(shipping_subsidy_value, 0), ' Off Shipping')
        WHEN seller_pays_shipping = true AND shipping_subsidy_type IS NOT NULL AND shipping_subsidy_type <> ''
          THEN 'Discounted Shipping'
        WHEN seller_pays_shipping = true
          THEN 'Discounted Shipping'
        ELSE 'Paid Shipping'
      END
    SQL

    # ═══ Product filters ═══
    product_cats = products.joins(:category)
                           .group("categories.name")
                           .count
                           .map { |name, count| { name: name, count: count } }
    product_prices = products.pluck(:price).compact
    product_price_range = {
      min: product_prices.min&.floor || 0,
      max: product_prices.max&.ceil || 0
    }
    product_ratings = (1..5).map do |star|
      count = products.where("rating >= ? AND rating < ?", star, star + 1).count
      { star: star, count: count }
    end
    product_delivery = products.group(Arel.sql(delivery_label_sql)).count
                               .reject { |k, _| k.nil? }
                               .map { |label, cnt| { label: label, count: cnt } }
                               .sort_by { |d| d[:label] }

    # ═══ Package filters ═══
    package_cats = packages.joins(:categories)
                           .group("categories.name")
                           .count
                           .map { |name, count| { name: name, count: count } }
    package_prices = packages.pluck(:price).compact
    package_price_range = {
      min: package_prices.min&.floor || 0,
      max: package_prices.max&.ceil || 0
    }
    package_ratings = []   # no rating distribution for packages

    # ★ NEW: delivery options for packages – uses Ruby helper, no column dependency
    package_delivery = packages.map { |pkg| compute_delivery_label(pkg) }
                               .tally
                               .map { |label, count| { label: label, count: count } }
                               .sort_by { |d| d[:label] }

    render json: {
      products: {
        categories: product_cats,
        ratings: product_ratings,
        price_range: product_price_range,
        delivery_options: product_delivery
      },
      packages: {
        categories: package_cats,
        ratings: package_ratings,
        price_range: package_price_range,
        delivery_options: package_delivery
      }
    }
  end

  # GET /api/v1/vendors/me
  def me
    skip_authorization   # ★ allow any authenticated user (Pundit safe)
    vendor = current_user&.vendor
    if vendor
      render json: vendor_summary_json(vendor).merge(
        status: vendor.status,
        rejection_reason: vendor.rejection_reason,
        description: vendor.description,
        phone: vendor.phone,
        national_id: vendor.national_id,
        tin: vendor.tin,
        business_address: vendor.business_address,
        bank_name: vendor.bank_name,
        account_number: vendor.account_number,
        account_name: vendor.account_name,
        telebirr_number: vendor.telebirr_number,
        logo_url: vendor.logo_url,
        banner_url: vendor.banner_url,
        license_document_url: vendor.license_document_url,
        commission_rate: vendor.effective_commission_rate,
        membership_plan: vendor.membership_plan ? {
          id: vendor.membership_plan.id,
          name: vendor.membership_plan.name,
          commission_rate: vendor.membership_plan.commission_rate
        } : nil,
        membership_expires_at: vendor.membership_expires_at,
        featured: vendor.featured,
        featured_until: vendor.featured_until
      )
    else
      render json: nil
    end
  end

  # PUT /api/v1/vendors/me
  def update_me
    vendor = current_user.vendor || current_user.build_vendor

    %w[national_id tin business_address is_bulk_supplier].each do |field|
      current_value = vendor.send(field)
      if field == 'is_bulk_supplier' ? !current_value.nil? : current_value.present?
        params[:vendor].delete(field)
      end
    end

    if vendor.license_document.attached?
      params[:vendor].delete(:business_license)
    end

    if vendor.update(vendor_update_params)
      vendor.logo.attach(params[:vendor][:logo]) if params[:vendor][:logo].present?
      vendor.banner.attach(params[:vendor][:banner]) if params[:vendor][:banner].present?
      if params[:vendor][:business_license].present? && !vendor.license_document.attached?
        vendor.license_document.attach(params[:vendor][:business_license])
      end

      render json: vendor_summary_json(vendor).merge(
        status: vendor.status,
        description: vendor.description,
        phone: vendor.phone,
        national_id: vendor.national_id,
        tin: vendor.tin,
        business_address: vendor.business_address,
        bank_name: vendor.bank_name,
        account_number: vendor.account_number,
        account_name: vendor.account_name,
        telebirr_number: vendor.telebirr_number,
        logo_url: vendor.logo_url,
        banner_url: vendor.banner_url,
        license_document_url: vendor.license_document_url,
        commission_rate: vendor.effective_commission_rate,
        membership_plan: vendor.membership_plan ? {
          id: vendor.membership_plan.id,
          name: vendor.membership_plan.name,
          commission_rate: vendor.membership_plan.commission_rate
        } : nil,
        membership_expires_at: vendor.membership_expires_at,
        featured: vendor.featured,
        featured_until: vendor.featured_until
      )
    else
      render json: { errors: vendor.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def vendor_update_params
    params.require(:vendor).permit(
      :business_name, :description, :phone,
      :bank_name, :account_number, :account_name, :telebirr_number,
      :national_id, :tin, :business_address, :is_bulk_supplier
    )
  end

  # ── JSON helpers ──
  def vendor_summary_json(vendor)
    {
      id: vendor.id,
      business_name: vendor.business_name,
      description: vendor.description,
      logo_url: vendor.logo_url,
      banner_url: vendor.banner_url,
      rating: vendor.rating.to_f,
      reviews_count: vendor.reviews_count,
      products_count: vendor.products_count,
      business_address: vendor.business_address,
      category: vendor.categories.first&.name || 'General',
      categories: vendor.categories.map { |c| { id: c.id, name: c.name } },
      accepting_orders: vendor.accepting_orders,
      reopen_at: vendor.reopen_at,
      is_bulk_supplier: vendor.is_bulk_supplier,
      is_company: vendor.enterprise?,
      membership_tier: vendor.membership_tier,
      badge: vendor.display_badge,              # ★ updated
      phone: vendor.user&.phone
    }
  end

  def vendor_detail_json(vendor)
    vendor_summary_json(vendor).merge(
      long_description: vendor.long_description,
      products: vendor.products.active.map { |p| product_json(p) },
      packages: vendor.packages.limit(10).map { |pkg| package_json(pkg) },
      discounts: vendor.products.active.where.not(discount: nil).or(
        vendor.products.active.where(is_flash_sale: true)
      ).limit(10).map { |p| product_json(p) },
      reviews: vendor.reviews.includes(:user).order(created_at: :desc).limit(5).map { |r| review_json(r) },
      return_policy: vendor.return_policy,
      shipping_policy: vendor.shipping_policy,
      payment_policy: vendor.payment_policy,
      latitude: vendor.business_lat,
      longitude: vendor.business_lng,
      full_address: vendor.business_address,
      total_sales: vendor.total_sales_count,
      membership_tier: vendor.membership_tier,
      badge: vendor.display_badge,              # ★ updated
      is_company: vendor.enterprise?,
      is_verified: vendor.status == 'approved',
      phone: vendor.user&.phone,
      banner_url: vendor.banner_url,
      business_address: vendor.business_address,
      categories: vendor.categories.map { |c| { id: c.id, name: c.name } }
    )
  end

  def product_json(product)
    eff_price = product.price.presence
    if eff_price.nil? && product.variants_data.is_a?(Array) && product.variants_data.first.is_a?(Hash)
      eff_price = product.variants_data.first['price']&.to_f
    end

    {
      id: product.id,
      title: product.title,
      price: product.price,
      effective_price: eff_price,
      original_price: product.original_price,
      rating: product.rating,
      reviews_count: product.reviews_count,
      sold_count: product.sold_count,
      free_shipping: product.free_shipping,
      delivery_label: product.delivery_label,
      seller_pays_shipping: product.seller_pays_shipping,
      shipping_subsidy_type: product.shipping_subsidy_type,
      shipping_subsidy_value: product.shipping_subsidy_value,
      discount: product.discount,
      is_flash_sale: product.is_flash_sale,
      flash_sale_price: product.flash_sale_price,
      is_super_deal: product.is_super_deal,
      super_deal_price: product.super_deal_price,
      image_urls: product.image_urls,
      bulk_enabled: product.bulk_enabled?,
      minimum_bulk_quantity: product.minimum_bulk_quantity,
      is_wholesale: product.bulk_enabled?,   # ★ FIXED: was product.bulk?
      description: product.respond_to?(:description) ? product.description : nil,
      specifications: product.respond_to?(:specifications) ? product.specifications : {},
      variants: product.respond_to?(:variants_data) ? product.variants_data || [] : [],
      category: product.category.present? ? { name: product.category.name } : nil,
      vendor: {
        id: product.vendor.id,
        business_name: product.vendor.business_name,
        membership_tier: product.vendor.membership_tier,
        badge: product.vendor.display_badge,     # ★ updated
        rating: product.vendor.average_rating,
        total_sales: product.vendor.total_sales_count,
        products_count: product.vendor.products_count
      }
    }
  end

  def package_json(package)
    {
      id: package.id,
      name: package.name,
      description: package.description,
      price: package.price.to_f,
      original_price: package.original_price,
      image_urls: package.image_urls,
      items_count: package.items_count,
      delivery_label: compute_delivery_label(package),
      categories: package.categories.map { |c| { name: c.name } },
      vendor: {
        business_name: package.vendor.business_name,
        badge: package.vendor.display_badge     # ★ updated
      }
    }
  end

  def review_json(review)
    {
      id: review.id,
      user: { name: review.user.full_name },
      rating: review.rating,
      comment: review.comment,
      created_at: review.created_at.strftime("%B %d, %Y"),
      verified: true
    }
  end

  def compute_delivery_label(pkg)
    return 'Free Shipping' if pkg.free_shipping == true

    if pkg.seller_pays_shipping == true
      type = pkg.shipping_subsidy_type
      val  = pkg.shipping_subsidy_value

      if type.present? && type != ''
        case type
        when 'percent' then return "#{val.to_i}% Off Shipping"
        when 'fixed'   then return "$#{val} Off Shipping"
        else                return 'Discounted Shipping'
        end
      else
        return 'Discounted Shipping'
      end
    end

    'Paid Shipping'
  end
end