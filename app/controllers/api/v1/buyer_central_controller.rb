module Api
  module V1
    class BuyerCentralController < ApplicationController
      include Authentication
      before_action :require_authentication

      def index
        user = current_user

        # ----- Recent orders (last 4) -----
        orders = user.orders.order(created_at: :desc).limit(4).map do |order|
          {
            id: order.id,
            date: order.created_at,
            total: order.total.to_f,
            status: order.status,
            items_count: order.line_items.count,
            estimated_delivery: order.respond_to?(:estimated_delivery) ? order.estimated_delivery : nil
          }
        end

        # ----- Recently viewed (last 12) -----
        recently = user.recently_vieweds.order(viewed_at: :desc).limit(12).includes(:product).map do |rv|
          p = rv.product
          next unless p
          eff_price = p.price.presence
          if eff_price.nil? && p.variants_data.is_a?(Array) && p.variants_data.first.is_a?(Hash)
            eff_price = p.variants_data.first['price']&.to_f
          end
          {
            id: p.id,
            title: p.title,
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
            variants: p.variants_data || []
          }
        end.compact

        # ----- Wishlist (first 12 items) -----
        wishlist = user.wishlist
        wishlist_items = if wishlist
          wishlist.wishlist_items.includes(:product).limit(12).map do |item|
            p = item.product
            next unless p
            eff_price = p.price.presence
            if eff_price.nil? && p.variants_data.is_a?(Array) && p.variants_data.first.is_a?(Hash)
              eff_price = p.variants_data.first['price']&.to_f
            end
            {
              id: p.id,
              title: p.title,
              price: p.price,
              effective_price: eff_price,
              original_price: p.original_price,
              rating: p.rating,
              reviews_count: p.reviews_count,
              discount: p.discount,
              image_urls: p.image_urls,
              free_shipping: p.free_shipping,
              sold_count: p.sold_count,
              stock: p.stock,
              is_flash_sale: p.is_flash_sale,
              flash_sale_price: p.flash_sale_price,
              flash_sale_ends_at: p.flash_sale_ends_at,
              is_super_deal: p.is_super_deal,
              super_deal_price: p.super_deal_price,
              super_deal_ends_at: p.super_deal_ends_at,
              category: p.category ? { id: p.category.id, name: p.category.name } : nil,
              vendor: p.vendor ? { id: p.vendor.id, business_name: p.vendor.business_name } : nil,
              product_attributes: p.product_attributes || {},
              variants: p.variants_data || []
            }
          end.compact
        else
          []
        end

        # ----- Saved searches (last 20) -----
        saved_searches = if defined?(SavedSearch) && user.respond_to?(:saved_searches)
          user.saved_searches.order(created_at: :desc).limit(20).map { |s| { id: s.id, query: s.query } }
        else
          []
        end

        # ----- Popular searches (system-wide) -----
        popular_searches = if defined?(SavedSearch)
          SavedSearch.group(:query).order(Arel.sql('COUNT(id) DESC')).limit(10).count.map { |q, c| { query: q, count: c } }
        else
          []
        end

        # ----- Spending stats -----
        all_orders = user.orders
        total_spent = all_orders.sum(:total).to_f
        current_year_orders = all_orders.where('created_at >= ?', Time.current.beginning_of_year)
        months_with_orders = current_year_orders.group("DATE_TRUNC('month', created_at)").count.size
        avg_monthly = months_with_orders > 0 ? (total_spent / months_with_orders).round(2) : 0.0

        spending_chart = (5.downto(0)).map do |i|
          month_start = i.months.ago.beginning_of_month
          month_end = i.months.ago.end_of_month
          spent = all_orders.where(created_at: month_start..month_end).sum(:total).to_f
          { month: month_start.strftime('%b'), amount: spent }
        end

        render json: {
          orders: orders,
          recently_viewed: recently,
          wishlist: wishlist_items,
          total_spent: total_spent,
          avg_monthly_spend: avg_monthly,
          spending_chart: spending_chart,
          saved_searches: saved_searches,
          popular_searches: popular_searches
        }
      end
    end
  end
end