module Api
  module V1
    class ProductsController < ApplicationController
      skip_before_action :require_authentication, only: [:index]

      def index
        products = Product.visible
                          .where(status: :active)
                          .joins(vendor: :user)
                          .where(users: { status: :active })
                          .where(vendors: { status: :approved })

        if params[:vendor_id].present?
          products = products.where(vendor_id: params[:vendor_id].to_i)
        end

        if params[:category].present?
          products = products.where(category_id: params[:category].to_i)
        end

        # Sorting – default popularity (sales + rating + membership tier)
        sort = params[:sort] || 'popular'
        case sort
        when 'newest'     then products = products.order(created_at: :desc)
        when 'price_asc'  then products = products.order(Arel.sql("COALESCE(products.price, (products.variants_data->0->>'price')::float) ASC"))
        when 'price_desc' then products = products.order(Arel.sql("COALESCE(products.price, (products.variants_data->0->>'price')::float) DESC"))
        when 'rating'     then products = products.order(rating: :desc)
        when 'best_sellers' then products = products.order(sold_count: :desc)
        when 'trending'   then products = products.order(views_count: :desc)
        else
          products = products.order(sold_count: :desc, rating: :desc)
                            .joins("LEFT JOIN membership_plans ON membership_plans.id = vendors.membership_plan_id")
                            .order(Arel.sql("COALESCE(membership_plans.price, 0) DESC"))
        end

        limit = params[:limit]&.to_i || params[:per_page]&.to_i || 5
        products = products.with_attached_images
                           .with_attached_videos
                           .includes(:vendor, :category)
                           .limit(limit)

        render json: {
          data: products.map { |p| format_product(p) }
        }
      end

      private

      def safe_f(val); val.to_f rescue 0.0; end
      def safe_i(val); val.to_i rescue 0; end

      # ★ Use the model's hardened current_price (respects flash/super deals)
      # For variant effective prices, apply only manual discount (deals are product-level)
      def variant_effective_price(product, variant_price)
        product.apply_discount_to(variant_price.to_f)
      end

      def main_image_for(product)
        urls = product.image_urls
        urls.is_a?(Array) && urls.any? ? urls.first : ''
      end

      def normalize_variant_attributes(variants)
        return variants unless variants.is_a?(Array)
        all_keys = variants.flat_map { |v| v['attributes']&.keys || [] }.uniq
        variants.each do |v|
          next unless v.is_a?(Hash)
          attrs = v['attributes'] || {}
          all_keys.each { |k| attrs[k] ||= "" }
          v['attributes'] = attrs
        end
        variants
      end

      def format_product(product)
        vendor = product.vendor

        # Enrich variants with individual effective prices (manual discount only)
        enriched_variants = normalize_variant_attributes(product.variants_data || []).map do |v|
          next v unless v.is_a?(Hash) && v['price'].present?
          v.merge('effective_price' => product.apply_discount_to(v['price'].to_f))
        end

        # ★ Use the model's current_price for the product-level effective price
        effective = product.current_price

        # ★ Handle unlimited stock properly (avoid Float::INFINITY in JSON)
        avail = product.available_stock
        available_stock_display = (avail == Float::INFINITY) ? nil : avail.to_i

        free_delivery = product.free_shipping? || (product.seller_pays_shipping? && product.shipping_subsidy_type == 'full')

        {
          id: product.id,
          title: product.title || '',
          price: safe_f(product.price),
          effective_price: effective.to_f,
          original_price: safe_f(product.original_price),
          discount: safe_i(product.discount_percentage),
          rating: safe_f(product.rating),
          reviews_count: safe_i(product.reviews_count),
          sold_count: safe_i(product.sold_count),
          free_shipping: product.free_shipping.present?,
          free_delivery: free_delivery,
          delivery_label: product.delivery_label,
          stock: safe_i(product.stock),
          available_stock: available_stock_display,
          image_urls: product.image_urls || [],
          image_url: main_image_for(product),
          product_attributes: product.product_attributes || {},
          variants: enriched_variants,
          vendor: vendor ? {
            id: vendor.id,
            business_name: vendor.business_name,
            accepting_orders: vendor.accepting_orders,
            reopen_at: vendor.reopen_at,
            rating: vendor.average_rating,
            products_count: vendor.products_count,
            logo_url: vendor.logo_url,
            membership_tier: vendor.membership_tier,
            total_sales: vendor.total_sales_count,
            badge: vendor.display_badge
          } : nil,
          bulk_enabled: product.bulk_enabled,
          minimum_bulk_quantity: product.minimum_bulk_quantity,
          orderable: product.can_be_ordered?(1),
          unavailable_reason: product.unavailable_reason,
          out_of_stock: product.out_of_stock?,
          variants_count: (product.variants_data || []).size
        }
      end
    end
  end
end