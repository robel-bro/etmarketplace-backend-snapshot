module Api
  module V1
    class PopularSearchesController < ApplicationController
      allow_unauthenticated_access only: [:index]

      def index
        suggestions = []

        # 1. 🔥 Trending products (most viewed)
        Product.where(status: :active)
               .where.not(title: nil)
               .order(views_count: :desc)
               .limit(6)
               .pluck(:title)
               .each { |title| suggestions << { type: 'product', query: title } }

        # 2. 📂 Popular categories
        Category.limit(4).pluck(:name)
                .each { |name| suggestions << { type: 'category', query: name } }

        # 3. 🔍 Trending user searches (filtered)
        SavedSearch.group(:query)
                   .order(Arel.sql('COUNT(id) DESC'))
                   .limit(4)
                   .count(:id)
                   .keys
                   .select { |q| q.length > 4 && q.length < 30 }
                   .each { |query| suggestions << { type: 'trending', query: query } }

        # Remove duplicates (case-insensitive), limit to 12
        unique = suggestions.uniq { |s| s[:query].downcase }.first(12)

        render json: unique
      end
    end
  end
end