# app/controllers/admin/products_controller.rb

class Admin::ProductsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActiveRecord::RecordNotDestroyed, with: :record_not_destroyed
  rescue_from ActiveRecord::InvalidForeignKey, with: :foreign_key_error
  rescue_from Faraday::ConnectionFailed, with: :search_engine_unavailable
  rescue_from Searchkick::Error, with: :search_engine_unavailable

  # GET /admin/products
  def index
    page = (params[:page] || 1).to_i
    per_page = [(params[:per_page] || 50).to_i, 200].min

    products = Product.includes(:vendor, :category, :product_variants)
                      .with_attached_images
                      .with_attached_videos
                      .order(created_at: :desc)
                      .limit(per_page)
                      .offset((page - 1) * per_page)
    total = Product.count

    product_ids = products.map(&:id)
    sold_map = Product.today_quantity_sold_map(product_ids)

    render json: {
      data: products.map { |p| admin_product_json(p, sold_map) },
      meta: {
        current_page: page,
        total_count: total,
        per_page: per_page,
        next_page: (page * per_page) < total ? page + 1 : nil,
        prev_page: page > 1 ? page - 1 : nil
      }
    }
  end

  # GET /admin/products/:id
  def show
    @product = Product.includes(:vendor, :category, :product_variants).find(params[:id])
    sold_map = Product.today_quantity_sold_map([@product.id])
    render json: admin_product_json(@product, sold_map)
  end

  # PATCH/PUT /admin/products/:id
  def update
    @product = Product.find(params[:id])

    without_searchkick_callbacks do
      # Handle image retention
      if params.dig(:product, :keep_image_ids).present?
        ids_to_keep = params[:product][:keep_image_ids].split(',').map(&:to_i).compact
        @product.images.where.not(id: ids_to_keep).each(&:purge)
      end
      if params.dig(:product, :keep_video_ids).present?
        ids_to_keep = params[:product][:keep_video_ids].split(',').map(&:to_i).compact
        @product.videos.where.not(id: ids_to_keep).each(&:purge)
      end

      # Attach new files
      if params.dig(:product, :images).present?
        params[:product][:images].each { |img| @product.images.attach(img) if img.respond_to?(:read) }
      end
      if params.dig(:product, :videos).present?
        params[:product][:videos].each { |vid| @product.videos.attach(vid) if vid.respond_to?(:read) }
      end

      # Parse JSON fields
      if params.dig(:product, :product_attributes).is_a?(String)
        @product.product_attributes = safe_parse_json(params[:product][:product_attributes])
      end
      if params.dig(:product, :variants).is_a?(String)
        @product.variants_data = normalize_variants(safe_parse_json(params[:product][:variants]))
      end

      # Bulk product with no stock → unlimited
      if @product.bulk_enabled? && params[:product][:stock].blank?
        params[:product][:stock] = nil
      end

      unless @product.update(admin_product_params)
        raise ActiveRecord::RecordInvalid, @product.errors.full_messages.to_sentence
      end
    end

    render json: admin_product_json(@product)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
  end

  # DELETE /admin/products/:id
  def destroy
    @product = Product.find(params[:id])

    without_searchkick_callbacks do
      # Clean up all child records and join tables
      @product.line_items.destroy_all
      CartItem.where(product_id: @product.id).destroy_all
      WishlistItem.where(product_id: @product.id).destroy_all
      PackageProduct.where(product_id: @product.id).destroy_all
      PriceAlert.where(product_id: @product.id).destroy_all
      RecentlyViewed.where(product_id: @product.id).destroy_all if defined?(RecentlyViewed)
      Comparison.where(product_id: @product.id).destroy_all       if defined?(Comparison)
      BulkOrderItem.where(product_id: @product.id).destroy_all    if defined?(BulkOrderItem)
      PromotionalSectionProduct.where(product_id: @product.id).destroy_all
      Reservation.where(product_id: @product.id).destroy_all

      # ★ NEW: Clean many-to-many join table for collections
      if defined?(CollectionProduct)
        CollectionProduct.where(product_id: @product.id).destroy_all
      else
        # Fallback if model not loaded: raw SQL
        if ActiveRecord::Base.connection.table_exists?(:collections_products)
          ActiveRecord::Base.connection.execute(
            "DELETE FROM collections_products WHERE product_id = #{@product.id}"
          )
        end
      end

      # ★ NEW: Clean other possible join tables that reference product_id
      [
        :collection_products,
        :comparison_products,
        :bulk_order_items,
        :package_products,
        :promotional_section_products,
        :reservations,
        :cart_items,
        :wishlist_items,
        :price_alerts,
        :recently_vieweds
      ].each do |table|
        next unless ActiveRecord::Base.connection.table_exists?(table)
        next if table == :collections_products  # already handled
        begin
          ActiveRecord::Base.connection.execute(
            "DELETE FROM #{table} WHERE product_id = #{@product.id}"
          )
        rescue => e
          Rails.logger.warn "Failed to clean #{table}: #{e.message}"
        end
      end

      @product.destroy!
    end

    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Product not found' }, status: :not_found
  rescue ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::StatementInvalid => e
    Rails.logger.error "Admin product destroy failed: #{e.message}"
    render json: { error: "Cannot delete: #{e.message}" }, status: :unprocessable_entity
  end

  private

  def admin_product_params
    params.require(:product).permit(
      :title, :description, :price, :original_price, :discount, :discount_type, :discount_value,
      :stock, :status, :category_id, :featured, :sponsored,
      :seller_pays_shipping, :free_shipping, :shipping_subsidy_type, :shipping_subsidy_value,
      :bulk_enabled, :minimum_bulk_quantity, :max_quantity_per_day,
      :weight_kg, :length_cm, :width_cm, :height_cm,
      :product_attributes, :variants,
      :keep_image_ids, :keep_video_ids,
      images: [], videos: []
    )
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
      v['stock'] = v['stock'].to_i if v['stock'].present?
      v
    end
  end

  def admin_product_json(product, sold_map = nil)
    sold_map ||= product.today_quantity_sold

    physical = if product.product_variants.any?
                 product.product_variants.sum do |pv|
                   pv.unlimited_stock? ? Float::INFINITY : (pv.stock - pv.reserved)
                 end
               elsif product.bulk_enabled? && product.stock.nil?
                 Float::INFINITY
               else
                 (product.stock || 0) - (product.stock_reserved || 0)
               end

    daily_limit = product.max_quantity_per_day
    if daily_limit.present?
      sold_today = sold_map.is_a?(Hash) ? (sold_map[product.id] || 0) : sold_map
      remaining = [daily_limit - sold_today, 0].max
      available = [physical, remaining].min
      available = 0 if available < 0
    else
      available = physical.to_f == Float::INFINITY ? Float::INFINITY : [physical, 0].max
    end

    stock_display = if product.bulk_enabled? && product.stock.nil? && product.product_variants.empty?
                      "Unlimited"
                    elsif available == Float::INFINITY
                      "Unlimited"
                    else
                      available.to_i.to_s
                    end

    {
      id: product.id,
      title: product.title,
      description: product.description,
      price: product.price,
      effective_price: product.current_price,
      original_price: product.original_price,
      discount_type: product.discount_type,
      discount_value: product.discount_value,
      discount: product.discount_percentage,
      rating: product.rating,
      reviews_count: product.reviews_count,
      sold_count: product.sold_count,
      free_shipping: product.free_shipping,
      free_delivery: product.free_shipping? || (product.seller_pays_shipping? && product.shipping_subsidy_type == 'full'),
      delivery_label: product.delivery_label,
      stock: product.stock,
      available_stock: available == Float::INFINITY ? nil : available.to_i,
      stock_display: stock_display,
      bulk_enabled: product.bulk_enabled,
      out_of_stock: available != Float::INFINITY && available <= 0,
      status: product.status,
      sponsored: product.sponsored,
      featured: product.featured,
      image_urls: product.image_urls,
      video_urls: product.video_urls,
      vendor: product.vendor ? { id: product.vendor.id, business_name: product.vendor.business_name } : nil,
      category: product.category ? { id: product.category.id, name: product.category.name } : nil,
      product_attributes: product.product_attributes || {},
      variants: product.variants_data || [],
      views_count: product.views_count,
      created_at: product.created_at,
      updated_at: product.updated_at
    }
  end

  def without_searchkick_callbacks
    Searchkick.callbacks(false) do
      yield
    end
  end

  def record_not_found
    render json: { error: 'Product not found' }, status: :not_found
  end

  def record_not_destroyed(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  def foreign_key_error(exception)
    Rails.logger.error "Admin product operation failed: #{exception.message}"
    render json: { error: "Cannot delete product because it has associated records." }, status: :unprocessable_entity
  end

  def search_engine_unavailable(exception)
    Rails.logger.warn "Search engine unavailable during admin product operation: #{exception.message}"
    head :no_content
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'products' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('products')
    head :forbidden
    false
  end
end