# app/controllers/api/v1/promotional_sections_controller.rb
module Api
  module V1
    class PromotionalSectionsController < ApplicationController
      allow_unauthenticated_access only: [:index]

      def index
        sections = PromotionalSection.where(is_active: true)
                                     .order(display_order: :asc)

        render json: sections.map { |s| section_json(s) }
      end

      private

      def section_json(section)
        live_products = section.fetch_products_by_type

        {
          id: section.id,
          name: section.name,
          slug: section.slug,
          section_type: section.section_type,
          display_order: section.display_order,
          products: live_products.map { |p| product_summary(p) }
        }
      end

      def product_summary(product)
        eff_price = product.price.presence
        if eff_price.nil? && product.variants_data.is_a?(Array) && product.variants_data.first.is_a?(Hash)
          eff_price = product.variants_data.first['price']&.to_f
        end
        eff_price = eff_price.to_f

        {
          id: product.id,
          title: product.title,
          price: product.price.to_f,
          effective_price: eff_price,
          original_price: product.original_price.to_f,
          image_urls: product.image_urls,
          discount: product.discount.to_i,
          rating: product.rating.to_f,
          sold_count: product.sold_count.to_i,
          is_flash_sale: product.is_flash_sale,
          flash_sale_price: product.flash_sale_price.to_f,
          flash_sale_ends_at: product.flash_sale_ends_at,
          is_super_deal: product.is_super_deal,
          super_deal_price: product.super_deal_price.to_f,
          super_deal_ends_at: product.super_deal_ends_at
        }
      end
    end
  end
end