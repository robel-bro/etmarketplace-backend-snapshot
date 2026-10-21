# app/controllers/api/v1/recently_vieweds_controller.rb
module Api
  module V1
    class RecentlyViewedsController < ApplicationController
      before_action :require_authentication

      # GET /api/v1/recently_vieweds
      def index
        items = current_user.recently_vieweds
                            .includes(:product)
                            .order(viewed_at: :desc)
                            .limit(20)
        render json: items.map { |rv| product_summary(rv.product) }
      end

      # POST /api/v1/recently_vieweds
      # params: { product_id: 123 }
      def create
        product = Product.visible.find(params[:product_id])
        recently_viewed = current_user.recently_vieweds.find_or_initialize_by(product_id: product.id)
        recently_viewed.viewed_at = Time.current

        if recently_viewed.save
          head :ok
        else
          render json: { errors: recently_viewed.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Product not found" }, status: :not_found
      end

      private

      def product_summary(product)
        {
          id: product.id,
          title: product.title,
          price: product.price,
          effective_price: product.effective_selling_price,
          image_urls: product.image_urls,
          category: product.category ? { id: product.category.id, name: product.category.name } : nil
        }
      end
    end
  end
end