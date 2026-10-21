module Api
  module V1
    class CollectionsController < ApplicationController
      allow_unauthenticated_access only: [:index, :show]

      def index
        page = (params[:page] || 1).to_i.clamp(1, 10_000)
        per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
        cache_key = "collections/v2/index/#{page}/#{per_page}"

        if (cached = Rails.cache.read(cache_key))
          return render json: cached, status: :ok
        end

        collections = Collection.where(is_active: true)
                                .order(display_order: :asc)
                                .includes(
                                  :cover_image_attachment,
                                  products: [
                                    :category,
                                    :product_variants,
                                    :images_attachments,
                                    :videos_attachments,
                                    vendor: :user
                                  ]
                                )

        result = collections.map do |c|
          # Filter in memory — avoids extra queries
          visible_products = c.products.select do |p|
            p.active? &&
              p.vendor.present? &&
              p.vendor.status == 'approved' &&
              p.vendor.user.present? &&
              p.vendor.user.status == 'active'
          end

          top_products = visible_products.first(4)

          {
            id: c.id,
            name: c.name,
            slug: c.slug,
            description: c.description,
            label: c.try(:label),
            cover_image_url: c.respond_to?(:cover_image_url) ? c.cover_image_url : (c.cover_image.attached? ? url_for(c.cover_image) : nil),
            product_count: visible_products.size,
            showcase_products: top_products.map { |p| product_summary(p) }
          }
        end

        Rails.cache.write(cache_key, result, expires_in: 60.seconds)
        render json: result
      end

      def show
        page = (params[:page] || 1).to_i.clamp(1, 10_000)
        per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
        cache_key = "collections/v2/show/#{params[:id]}/#{page}/#{per_page}"

        if (cached = Rails.cache.read(cache_key))
          return render json: cached, status: :ok
        end

        collection = Collection.find_by(slug: params[:id])

        if collection && collection.is_active?
          visible_products = collection.products
                                       .merge(Product.visible)
                                       .joins(vendor: :user)
                                       .where(users: { status: :active })
                                       .where(vendors: { status: :approved })
                                       .includes(
                                         :category,
                                         :product_variants,
                                         :images_attachments,
                                         :videos_attachments,
                                         vendor: :user
                                       )

          products_page = visible_products.page(page).per(per_page)
          top_products = visible_products.limit(4)

          result = {
            id: collection.id,
            name: collection.name,
            slug: collection.slug,
            description: collection.description,
            label: collection.try(:label),
            cover_image_url: collection.respond_to?(:cover_image_url) ? collection.cover_image_url : (collection.cover_image.attached? ? url_for(collection.cover_image) : nil),
            product_count: visible_products.size,
            showcase_products: top_products.map { |p| product_summary(p) },
            products: products_page.map { |p| product_summary(p) },
            total_count: products_page.total_count,
            current_page: products_page.current_page,
            total_pages: products_page.total_pages
          }

          Rails.cache.write(cache_key, result, expires_in: 60.seconds)
          render json: result
        else
          render json: { error: "Collection not found" }, status: :not_found
        end
      end

      private

      # Normalize variant attributes so every variant has the same keys
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

      def product_summary(product)
        return {} if product.nil?

        base_price = product.price.to_f

        variant_prices = (product.variants_data || [])
          .map { |v| v.is_a?(Hash) ? v['price'].to_f : 0.0 }
          .select { |p| p > 0 }

        eff_price = if variant_prices.any?
                      variant_prices.map { |p| product.apply_discount_to(p) }.min
                    elsif product.price.present? && product.price > 0
                      # Uses current_price so discounts/flash/super are reflected
                      product.current_price
                    else
                      base_price
                    end
        eff_price = eff_price.presence&.to_f

        discount_pct = product.discount_percentage.to_i
        discount_pct = nil if discount_pct == 0

        original_price = product.original_price.to_f
        original_price = nil if original_price == 0.0

        flash_price = product.flash_sale_price.to_f
        flash_price = nil if flash_price == 0.0

        super_price = product.super_deal_price.to_f
        super_price = nil if super_price == 0.0

        vendor = product.vendor

        free_delivery = product.free_shipping? ||
          (product.seller_pays_shipping? && product.shipping_subsidy_type == 'full')
        delivery_label = product.delivery_label

        enriched_variants = normalize_variant_attributes(product.variants_data || []).map do |v|
          next v unless v.is_a?(Hash) && v['price'].present?
          v.merge('effective_price' => product.apply_discount_to(v['price'].to_f))
        end

        {
          id: product.id,
          title: product.title,
          description: product.description,
          price: base_price,
          effective_price: eff_price,
          original_price: original_price,
          discount: discount_pct,
          rating: product.rating.to_f,
          reviews_count: product.reviews_count.to_i,
          sold_count: product.sold_count.to_i,
          stock: product.stock.to_i,
          free_shipping: product.free_shipping?,
          free_delivery: free_delivery,
          delivery_label: delivery_label,
          seller_pays_shipping: product.seller_pays_shipping?,
          shipping_subsidy_type: product.shipping_subsidy_type,
          shipping_subsidy_value: product.shipping_subsidy_value.to_f,
          is_flash_sale: product.is_flash_sale,
          flash_sale_price: flash_price,
          flash_sale_ends_at: product.flash_sale_ends_at,
          is_super_deal: product.is_super_deal,
          super_deal_price: super_price,
          super_deal_ends_at: product.super_deal_ends_at,
          is_trending: product.is_trending,
          is_hot_deal: product.is_hot_deal,
          sponsored: product.sponsored,
          featured: product.featured,
          views_count: product.views_count.to_i,
          image_urls: product.image_urls,
          video_urls: product.video_urls,
          category: product.category ? { id: product.category.id, name: product.category.name } : nil,
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
          product_attributes: product.product_attributes || {},
          variants: enriched_variants,
          variants_count: (product.variants_data || []).size,
          bulk_enabled: product.bulk_enabled,
          minimum_bulk_quantity: product.minimum_bulk_quantity,
          max_quantity_per_day: product.max_quantity_per_day,
          is_wholesale: product.bulk_enabled?
        }
      rescue => e
        Rails.logger.error "product_summary failed for product #{product&.id}: #{e.message}"
        {}
      end
    end
  end
end