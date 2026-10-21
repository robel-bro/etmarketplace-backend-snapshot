class Seller::PackagesController < Seller::BaseController
  before_action :set_package, only: [:show, :update, :destroy]

  def index
    @packages = current_user.vendor.packages
                              .includes(:categories, :products)
                              .order(created_at: :desc)
    render json: @packages.map { |pkg| package_json(pkg) }
  end

  def show
    render json: package_json(@package)
  end

  def create
    @package = current_user.vendor.packages.build(package_params.except(:images, :videos))
    if params[:package][:category_ids].present?
      @package.categories = Category.where(id: params[:package][:category_ids])
    end
    product_ids = params.dig(:package, :product_ids) || []
    products = current_user.vendor.products.where(id: product_ids)
    if products.count != product_ids.uniq.count
      render json: { error: "One or more products do not belong to you" }, status: :unprocessable_entity and return
    end
    @package.products = products

    if @package.save
      attach_images(@package, params[:package][:images]) if params[:package][:images].present?
      attach_videos(@package, params[:package][:videos]) if params[:package][:videos].present?
      render json: package_json(@package), status: :created
    else
      render json: { errors: @package.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @package.update(package_params.except(:images, :videos))
      if params[:package][:category_ids].present?
        @package.categories = Category.where(id: params[:package][:category_ids])
      end
      if params[:package][:product_ids].present?
        product_ids = params[:package][:product_ids].map(&:to_i).uniq
        products = current_user.vendor.products.where(id: product_ids)
        if products.count != product_ids.count
          render json: { error: "One or more products do not belong to you" }, status: :unprocessable_entity and return
        end
        @package.products = products
      end

      keep_image_ids = params.dig(:package, :keep_image_ids)
      if keep_image_ids.present?
        ids = keep_image_ids.split(',').map(&:to_i).compact
        @package.images.where.not(id: ids).each(&:purge)
      end
      keep_video_ids = params.dig(:package, :keep_video_ids)
      if keep_video_ids.present?
        ids = keep_video_ids.split(',').map(&:to_i).compact
        @package.videos.where.not(id: ids).each(&:purge)
      end

      attach_images(@package, params[:package][:images]) if params[:package][:images].present?
      attach_videos(@package, params[:package][:videos]) if params[:package][:videos].present?
      render json: package_json(@package)
    else
      render json: { errors: @package.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @package.destroy
    head :no_content
  end

  private

  def set_package
    @package = current_user.vendor.packages.find(params[:id])
  end

  def package_params
    params.require(:package).permit(
      :name, :description, :price, :stock, :status, :featured,
      :discount_type, :discount_value, :discount_start, :discount_end,
      :original_price, :features,
      :shipping_type, :shipping_value,
      :seller_pays_shipping, :shipping_subsidy_type, :shipping_subsidy_value,
      :keep_image_ids, :keep_video_ids,
      category_ids: [], product_ids: [], images: [], videos: []
    )
  end

  def attach_images(pkg, imgs)
    imgs.each { |img| pkg.images.attach(img) }
  end

  def attach_videos(pkg, vids)
    vids.each { |vid| pkg.videos.attach(vid) }
  end

  def package_json(pkg)
    {
      id: pkg.id,
      name: pkg.name,
      description: pkg.description,
      price: pkg.current_price,
      original_price: pkg.original_price,
      discount_type: pkg.discount_type,
      discount_value: pkg.discount_value,
      discount_percentage: pkg.discount_percentage,
      stock: pkg.stock,
      featured: pkg.featured,
      status: pkg.status,
      image_urls: pkg.image_urls,
      video_urls: pkg.video_urls,
      items_count: pkg.items_count,
      shipping_type: pkg.shipping_type,
      shipping_value: pkg.shipping_value,
      seller_pays_shipping: pkg.seller_pays_shipping?,
      shipping_subsidy_type: pkg.shipping_subsidy_type,
      shipping_subsidy_value: pkg.shipping_subsidy_value,
      features: pkg.features || [],
      vendor: { id: pkg.vendor.id, business_name: pkg.vendor.business_name },
      categories: pkg.categories.map { |c| { id: c.id, name: c.name } },
      products: pkg.products.map do |pr|
        eff_price = pr.current_price.presence
        if eff_price.nil? && pr.variants_data.is_a?(Array) && pr.variants_data.first.is_a?(Hash)
          eff_price = pr.variants_data.first['price']&.to_f
        end
        { id: pr.id, title: pr.title, price: pr.price,
          effective_price: eff_price, image_urls: pr.image_urls, video_urls: pr.video_urls }
      end
    }
  end
end