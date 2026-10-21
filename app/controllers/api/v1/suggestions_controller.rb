# app/controllers/api/v1/suggestions_controller.rb
module Api
  module V1
    class SuggestionsController < ApplicationController
      skip_before_action :require_authentication

      def index
        query = params[:q].to_s.strip.downcase
        if query.blank?
          return render json: empty_suggestions
        end

        # Cache results for 2 minutes
        cache_key = "suggestions:#{query}"
        response = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
          {
            products:   product_suggestions(query),
            packages:   package_suggestions(query),
            categories: category_suggestions(query),
            brands:     brand_suggestions(query),
            popular_searches: popular_search_terms
          }
        end

        render json: response
      end

      private

      def empty_suggestions
        {
          products: [],
          packages: [],
          categories: [],
          brands: [],
          popular_searches: popular_search_terms
        }
      end

      def product_suggestions(query)
        Product.visible
               .where("LOWER(title) LIKE ?", "%#{query}%")
               .limit(5)
               .pluck(:id, :title, :price)
               .map do |id, title, price|
                 { id: id, title: title, image_url: Product.find(id).first_image_url, price: price }
               end
      rescue => e
        Rails.logger.warn "Product suggestions failed: #{e.message}"
        []
      end

      def package_suggestions(query)
        Package.visible
               .where("LOWER(name) LIKE ?", "%#{query}%")
               .limit(3)
               .pluck(:id, :name, :price)
               .map do |id, name, price|
                 { id: id, name: name, image_url: Package.find(id).image_urls.first, price: price }
               end
      rescue => e
        Rails.logger.warn "Package suggestions failed: #{e.message}"
        []
      end

      def category_suggestions(query)
        # Use ILIKE first, which is safer and works with pg_trgm automatically
        Category.where("LOWER(name) LIKE ?", "%#{query}%")
                .limit(5)
                .pluck(:id, :name)
                .map { |id, name| { id: id, name: name, slug: name.parameterize } }
      rescue => e
        Rails.logger.warn "Category suggestions failed: #{e.message}"
        []
      end

      def brand_suggestions(query)
        Product.visible
               .where("LOWER(product_attributes->>'brand') LIKE ?", "%#{query}%")
               .where.not("product_attributes->>'brand' IS NULL")
               .distinct
               .pluck(Arel.sql("product_attributes->>'brand'"))
               .compact
               .first(5)
               .map { |brand| { name: brand } }
      rescue => e
        Rails.logger.warn "Brand suggestions failed: #{e.message}"
        []
      end

      def popular_search_terms
        # If PopularSearch model exists, replace with actual data.
        # For now fallback to a sensible default.
        %w[electronics fashion shoes laptops].map { |term| { query: term } }
      end
    end
  end
end