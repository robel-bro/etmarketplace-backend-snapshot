class CategoriesController < ApplicationController
  allow_unauthenticated_access only: [:index, :show]

  def index
    categories = Category.includes(:image_attachment).all

    # Build a lookup hash of category_id => product count
    product_counts = Product.group(:category_id).count

    render json: categories.map { |c| build_category_hash(c, product_counts) }
  end

  def show
    @category = Category.includes(:image_attachment).find(params[:id])
    subcategories = @category.children.includes(:image_attachment)
    product_counts = Product.group(:category_id).count

    render json: build_category_hash(@category, product_counts).merge(
      children: subcategories.map { |c| build_category_hash(c, product_counts) }
    )
  end

  private

  def build_category_hash(category, product_counts = {})
    # Use the same host/port logic as Product, Vendor, and BannersController
    host = ActiveStorage::Current.url_options&.dig(:host) || 'localhost'
    port = ActiveStorage::Current.url_options&.dig(:port) || 3000

    img_url = if category.image.attached?
                Rails.application.routes.url_helpers.rails_blob_url(
                  category.image,
                  host: host,
                  port: port,
                  only_path: false
                )
              else
                category[:image]
              end

    {
      id: category.id,
      name: category.name,
      description: category.description,
      image_url: img_url,
      parent_id: category.parent_id,
      ancestry: category.ancestry,
      product_count: product_counts[category.id].to_i
    }
  end
end