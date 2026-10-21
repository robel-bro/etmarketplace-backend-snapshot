class WishlistsController < ApplicationController
  include Authentication
  before_action :require_authentication

  def show
    wishlist = current_user.wishlist || current_user.create_wishlist
    render json: wishlist_json(wishlist)
  end

  def add_item
    product = Product.find(params[:product_id])
    wishlist = current_user.wishlist || current_user.create_wishlist
    wishlist.wishlist_items.find_or_create_by!(product: product)
    render json: wishlist_json(wishlist)
  end

  def remove_item
    wishlist = current_user.wishlist
    wishlist&.wishlist_items&.find_by(product_id: params[:id])&.destroy
    render json: wishlist_json(wishlist || current_user.create_wishlist)
  end

  def merge
    guest_items = params[:items] || []
    wishlist = current_user.wishlist || current_user.create_wishlist

    guest_items.each do |item|
      product_id = item[:product_id] || item['product_id']
      next unless product_id
      product = Product.find_by(id: product_id)
      next unless product
      wishlist.wishlist_items.find_or_create_by!(product: product)
    end

    render json: wishlist_json(wishlist)
  end

  private

  def wishlist_json(wishlist)
    {
      id: wishlist.id,
      items: wishlist.wishlist_items.includes(:product).map do |item|
        p = item.product
        next unless p
        eff_price = p.price.presence
        if eff_price.nil? && p.variants_data.is_a?(Array) && p.variants_data.first.is_a?(Hash)
          eff_price = p.variants_data.first['price']&.to_f
        end
        {
          id: item.id,
          product_id: p.id,
          title: p.title,
          description: p.description,
          price: p.price,
          effective_price: eff_price,
          original_price: p.original_price,
          rating: p.rating,
          reviews_count: p.reviews_count,
          sold_count: p.sold_count,
          free_shipping: p.free_shipping,
          discount: p.discount,
          stock: p.stock,
          image_urls: p.image_urls,
          is_flash_sale: p.is_flash_sale,
          flash_sale_price: p.flash_sale_price,
          flash_sale_ends_at: p.flash_sale_ends_at,
          is_super_deal: p.is_super_deal,
          super_deal_price: p.super_deal_price,
          super_deal_ends_at: p.super_deal_ends_at,
          category: p.category ? { id: p.category.id, name: p.category.name } : nil,
          vendor: p.vendor ? { id: p.vendor.id, business_name: p.vendor.business_name } : nil,
          product_attributes: p.product_attributes || {},
          variants: p.variants_data || [],
          # ★ Bulk fields
          bulk_enabled: p.bulk_enabled?,
          minimum_bulk_quantity: p.minimum_bulk_quantity
        }
      end.compact
    }
  end
end