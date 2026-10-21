# app/controllers/admin/packages_controller.rb

class Admin::PackagesController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActiveRecord::RecordNotDestroyed, with: :record_not_destroyed
  rescue_from ActiveRecord::InvalidForeignKey, with: :foreign_key_error
  rescue_from Faraday::ConnectionFailed, with: :search_engine_unavailable
  rescue_from Searchkick::Error, with: :search_engine_unavailable

  # GET /admin/packages
  def index
    page = (params[:page] || 1).to_i
    per_page = [(params[:per_page] || 50).to_i, 200].min

    scope = Package.includes(:vendor, :categories, :package_products)
                   .with_attached_images
                   .with_attached_videos
                   .order(created_at: :desc)

    if params[:search].present?
      term = "%#{params[:search].downcase}%"
      scope = scope.joins(:vendor).where(
        'LOWER(packages.name) LIKE :term OR LOWER(vendors.business_name) LIKE :term',
        term: term
      )
    end

    if params[:status].present? && Package.statuses.key?(params[:status])
      scope = scope.where(status: params[:status])
    end

    total = scope.count
    packages = scope.limit(per_page).offset((page - 1) * per_page)

    render json: {
      data: packages.map { |pkg| admin_package_json(pkg) },
      meta: {
        current_page: page,
        per_page: per_page,
        total_count: total,
        next_page: (page * per_page) < total ? page + 1 : nil,
        prev_page: page > 1 ? page - 1 : nil
      }
    }
  end

  # GET /admin/packages/:id
  def show
    @package = Package.includes(:vendor, :categories, :package_products).find(params[:id])
    render json: admin_package_json(@package)
  end

  # PATCH/PUT /admin/packages/:id
  def update
    @package = Package.find(params[:id])

    without_searchkick_callbacks do
      # Handle image retention
      if params.dig(:package, :keep_image_ids).present?
        ids_to_keep = params[:package][:keep_image_ids].split(',').map(&:to_i).compact
        @package.images.where.not(id: ids_to_keep).each(&:purge)
      end
      if params.dig(:package, :keep_video_ids).present?
        ids_to_keep = params[:package][:keep_video_ids].split(',').map(&:to_i).compact
        @package.videos.where.not(id: ids_to_keep).each(&:purge)
      end

      # Attach new files
      if params.dig(:package, :images).present?
        params[:package][:images].each { |img| @package.images.attach(img) if img.respond_to?(:read) }
      end
      if params.dig(:package, :videos).present?
        params[:package][:videos].each { |vid| @package.videos.attach(vid) if vid.respond_to?(:read) }
      end

      # Parse features if string
      if params.dig(:package, :features).is_a?(String)
        @package.features = safe_parse_json(params[:package][:features])
      end

      # Bulk package no stock -> unlimited
      if params.dig(:package, :bulk_enabled).present? && params[:package][:bulk_enabled].to_s == 'true' && params[:package][:stock].blank?
        params[:package][:stock] = nil
      end

      unless @package.update(admin_package_params)
        raise ActiveRecord::RecordInvalid, @package.errors.full_messages.to_sentence
      end
    end

    render json: admin_package_json(@package)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: @package.errors.full_messages }, status: :unprocessable_entity
  end

  # DELETE /admin/packages/:id
  def destroy
    @package = Package.find(params[:id])

    without_searchkick_callbacks do
      @package.reviews.destroy_all
      @package.package_products.destroy_all
      @package.package_categories.destroy_all
      @package.destroy!
    end

    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Package not found' }, status: :not_found
  rescue ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::StatementInvalid => e
    Rails.logger.error "Admin package destroy failed: #{e.message}"
    render json: { error: "Cannot delete: #{e.message}" }, status: :unprocessable_entity
  end

  private

  def admin_package_params
    params.require(:package).permit(
      :name, :description, :price, :original_price,
      :discount_type, :discount_value, :stock, :status,
      :bulk_enabled,
      :seller_pays_shipping, :free_shipping,
      :shipping_subsidy_type, :shipping_subsidy_value,
      :keep_image_ids, :keep_video_ids,
      :features, category_ids: [],
      images: [], videos: []
    )
  end

  def safe_parse_json(str)
    JSON.parse(str)
  rescue JSON::ParserError
    nil
  end

  def admin_package_json(package)
    available = package.available_stock
    stock_display = if package.bulk_enabled? && package.stock.nil?
                      "Unlimited"
                    elsif available == Float::INFINITY
                      "Unlimited"
                    else
                      available.to_i.to_s
                    end

    {
      id: package.id,
      name: package.name,
      description: package.description,
      price: package.price,
      effective_price: package.current_price,
      original_price: package.original_price,
      discount_type: package.discount_type,
      discount_value: package.discount_value,
      discount_percentage: package.discount_percentage,
      stock: package.stock,
      available_stock: available == Float::INFINITY ? nil : available.to_i,
      stock_display: stock_display,
      bulk_enabled: package.bulk_enabled,
      status: package.status,
      out_of_stock: available != Float::INFINITY && available <= 0,
      free_shipping: package.free_shipping?,
      free_delivery: package.free_delivery?,
      delivery_label: package.delivery_label,
      image_urls: package.image_urls,
      video_urls: package.video_urls,
      vendor: package.vendor ? { id: package.vendor.id, business_name: package.vendor.business_name } : nil,
      categories: package.categories.map { |c| { id: c.id, name: c.name } },
      items_count: package.package_products.size,
      features: package.features || [],
      created_at: package.created_at,
      updated_at: package.updated_at
    }
  end

  def without_searchkick_callbacks
    Searchkick.callbacks(false) do
      yield
    end
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'packages' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('packages')
    head :forbidden
    false
  end

  def record_not_found
    render json: { error: 'Package not found' }, status: :not_found
  end

  def record_not_destroyed(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  def foreign_key_error(exception)
    Rails.logger.error "Admin package operation failed: #{exception.message}"
    render json: { error: "Cannot delete package because it has associated records." }, status: :unprocessable_entity
  end

  def search_engine_unavailable(exception)
    Rails.logger.warn "Search engine unavailable during admin package operation: #{exception.message}"
    head :no_content
  end
end