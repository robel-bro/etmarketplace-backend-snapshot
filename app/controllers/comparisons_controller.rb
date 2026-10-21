class ComparisonsController < ApplicationController
  before_action :require_authentication

  # GET /comparisons
  def index
    comparisons = current_user.comparisons.includes(product: [:vendor, :category])
    render json: comparisons.map { |c|
      product_json(c.product).merge(
        variant_attributes: c.variant_attributes || {}
      )
    }
  end

  # POST /comparisons
  def create
    product = Product.find(params[:product_id])
    variant_attrs = (params[:variant] || {}).to_unsafe_h rescue {}

    if current_user.comparisons.count >= 6
      render json: { error: "You can compare up to 6 products." }, status: :unprocessable_entity
      return
    end

    comp = current_user.comparisons.find_or_initialize_by(product: product)
    comp.variant_attributes = variant_attrs if variant_attrs.present?
    comp.save!
    head :ok
  end

  # DELETE /comparisons/:id  (id = product_id)
  def destroy
    current_user.comparisons.find_by(product_id: params[:id])&.destroy
    head :no_content
  end

  private

  def product_json(product)
    eff_price = product.price.presence
    if eff_price.nil? && product.variants_data.is_a?(Array) && product.variants_data.first.is_a?(Hash)
      eff_price = product.variants_data.first['price']&.to_f
    end

    {
      id: product.id,
      title: product.title,
      description: product.description,
      price: product.price,
      effective_price: eff_price,
      original_price: product.original_price,
      rating: product.rating,
      reviews_count: product.reviews_count,
      sold_count: product.sold_count,
      free_shipping: product.free_shipping,
      discount: product.discount,
      stock: product.stock,
      featured: product.featured,
      is_flash_sale: product.is_flash_sale,
      flash_sale_price: product.flash_sale_price,
      flash_sale_ends_at: product.flash_sale_ends_at,
      is_super_deal: product.is_super_deal,
      super_deal_price: product.super_deal_price,
      super_deal_ends_at: product.super_deal_ends_at,
      image_urls: product.image_urls,
      category: product.category ? { id: product.category.id, name: product.category.name } : nil,
      vendor: product.vendor ? { id: product.vendor.id, business_name: product.vendor.business_name } : nil,
      product_attributes: product.product_attributes || {},
      variants: product.variants_data || []
    }
  end
end