# app/controllers/api/v1/search_controller.rb
module Api
  module V1
    class SearchController < ApplicationController
      skip_before_action :require_authentication

      SORT_OPTIONS = %w[relevance price_asc price_desc newest trending best_sellers rating].freeze
      MAX_RESULTS_FOR_SORT = 200

      def index
        query = params[:q].to_s.strip
        if query.blank?
          render json: { data: [], meta: { total_count: 0, dominant_category: nil, filters: {}, suggestion: nil, suggestion_product_id: nil, sponsored: [], featured: [] } }
          return
        end

        page     = (params[:page] || 1).to_i
        per_page = (params[:per_page] || params[:limit] || 28).to_i
        sort     = params[:sort].presence || 'relevance'
        sort     = 'relevance' unless SORT_OPTIONS.include?(sort)

        # Simple synonym expansion
        expanded = query.downcase.strip
        synonyms = {
          'men fashion'   => "men's fashion",
          'women fashion' => "women's fashion",
          'cell phone'    => 'mobile phone',
          'smart phone'   => 'mobile phone',
        }
        synonyms.each { |from, to| expanded = expanded.gsub(/\b#{Regexp.escape(from)}\b/, to) }
        expanded = expanded.squeeze(' ').strip

        # ---- Category browsing (with full filter support) ----
        category = Category.where("LOWER(name) LIKE ?", "%#{expanded.downcase}%").first
        if category
          descendant_ids = category.subtree_ids

          if params[:category].present?
            chosen_ids = params[:category].to_s.split(',').map(&:to_i)
            chosen_descendants = chosen_ids.flat_map { |id| Category.find_by(id: id)&.subtree_ids || [] }.uniq
            descendant_ids &= chosen_descendants unless chosen_descendants.empty?
          end

          products = Product.visible
                            .where(status: :active)
                            .where(category_id: descendant_ids)

          # Brand filter
          if params[:brand].present?
            brands = params[:brand].to_s.split(',').map(&:strip).map(&:downcase)
            products = products.where(
              "LOWER(products.product_attributes->>'brand') IN (?)", brands
            )
          end

          # Price range
          if params[:price_min].present? || params[:price_max].present?
            price_condition = "COALESCE(products.price, (products.variants_data->0->>'price')::float)"
            products = products.where("#{price_condition} >= ?", params[:price_min].to_f) if params[:price_min].present?
            products = products.where("#{price_condition} <= ?", params[:price_max].to_f) if params[:price_max].present?
          end

          # Rating filter
          if params[:rating].present?
            products = products.where("products.rating >= ?", params[:rating].to_f)
          end

          # Shipping filter – uses model's delivery_label logic
          if params[:delivery].present?
            delivery_options = params[:delivery].to_s.split(',').map(&:strip)
            conditions = []
            conditions << "products.free_shipping = true" if delivery_options.include?("Free Delivery")
            conditions << "(products.seller_pays_shipping = true AND products.shipping_subsidy_type = 'full')" if delivery_options.include?("Free Delivery")
            conditions << "(products.seller_pays_shipping = true AND products.shipping_subsidy_type = 'percent')" if delivery_options.any? { |opt| opt.include?('%') }
            if delivery_options == ["Paid Delivery"]
              products = products.where("products.free_shipping = false AND (products.seller_pays_shipping = false OR products.shipping_subsidy_type IS NULL)")
            else
              products = products.where(conditions.join(" OR ")) unless conditions.empty?
            end
          end

          products = products.joins(:vendor)

          # Apply sort – SMART default uses trending_score
          case sort
          when 'price_asc'
            products = products.order(Arel.sql("COALESCE(products.price, (products.variants_data->0->>'price')::float) ASC"))
          when 'price_desc'
            products = products.order(Arel.sql("COALESCE(products.price, (products.variants_data->0->>'price')::float) DESC"))
          when 'newest'
            products = products.order(created_at: :desc)
          when 'trending'
            products = products.order(trending_score: :desc, views_count: :desc, sold_count: :desc, rating: :desc)
          when 'best_sellers'
            products = products.order(sold_count: :desc)
          when 'rating'
            products = products.order(rating: :desc)
          else
            # Smart default
            products = products.order(trending_score: :desc, sold_count: :desc, views_count: :desc)
                               .joins("LEFT JOIN membership_plans ON membership_plans.id = vendors.membership_plan_id")
                               .order(Arel.sql("COALESCE(membership_plans.price, 0) DESC"))
          end

          total   = products.count
          results = products.limit(per_page).offset((page - 1) * per_page)
                            .map { |p| product_to_result(p) }

          results = apply_attribute_filters(results)

          sponsored = Product.visible
                             .where(status: :active, sponsored: true)
                             .where(category_id: descendant_ids)
                             .limit(3)
                             .map { |p| product_to_result(p).merge(sponsored: true) }

          featured = Product.visible
                            .where(status: :active, featured: true)
                            .where(category_id: descendant_ids)
                            .limit(5)
                            .map { |p| product_to_result(p).merge(featured: true) }

          render json: {
            data: results,
            meta: {
              current_page: page,
              next_page: (page * per_page) < total ? page + 1 : nil,
              total_count: total,
              per_page: per_page,
              dominant_category: { id: category.id, name: category.name },
              filters: build_filters_for(products),
              suggestion: nil,
              suggestion_product_id: nil,
              sponsored: sponsored,
              featured: featured
            }
          }
          return
        end

        # ---- Prepare Searchkick where clauses ----
        where = { status: 'active', vendor_status: 'approved' }
        if params[:category].present?
          cat_ids = params[:category].to_s.split(',').map(&:to_i)
          descendant_ids = cat_ids.flat_map { |id| Category.find_by(id: id)&.subtree_ids || [] }.uniq
          where[:category_id] = descendant_ids unless descendant_ids.empty?
        end
        if params[:brand].present?
          where[:brand] = params[:brand].to_s.split(',').map { |b| b.strip.downcase }
        end
        if params[:price_min].present? || params[:price_max].present?
          where[:price] = {}
          where[:price][:gte] = params[:price_min].to_f if params[:price_min].present?
          where[:price][:lte] = params[:price_max].to_f if params[:price_max].present?
        end
        if params[:rating].present?
          where[:rating] = { gte: params[:rating].to_f }
        end
        if params[:delivery].present?
          where[:delivery_type] = params[:delivery].to_s.split(',').map(&:strip)
        end

        if expanded.match?(/\bmen\b|men's/)
          exclude_ids = [135]
          if where[:category_id].present?
            where[:category_id] = { in: where[:category_id], not: exclude_ids }
          else
            where[:category_id] = { not: exclude_ids }
          end
        end

        fetch_size = sort == 'relevance' ? per_page : MAX_RESULTS_FOR_SORT

        # ========== PRODUCT SEARCH (no suggest) ==========
        product_results = begin
          Product.search(
            expanded,
            where: where,
            fields: [:title, :description, :brand, :category_name, :product_attributes_text],
            operator: expanded.split.size > 1 ? 'and' : 'or',
            boost_by: { sold_count: { factor: 5 }, views_count: { factor: 2 } },
            misspellings: { edit_distance: 2 },
            body_options: { min_score: 0.5 },
            page: 1,
            per_page: fetch_size
          )
        rescue => e
          Rails.logger.error "Product search error: #{e.message}"
          Searchkick::Results.new(Product.none, expanded, {})
        end

        # ========== PACKAGE SEARCH (no suggest) ==========
        package_results = begin
          Package.search(
            expanded,
            where: { status: 'active', vendor_status: 'approved' },
            fields: [:name, :description, :category_names],
            operator: expanded.split.size > 1 ? 'and' : 'or',
            misspellings: { edit_distance: 2 },
            body_options: { min_score: 0.5 },
            page: 1,
            per_page: fetch_size
          )
        rescue => e
          Rails.logger.error "Package search error: #{e.message}"
          Searchkick::Results.new(Package.none, expanded, {})
        end

        # ---- Fallback suggestion using PostgreSQL similarity ----
        suggestion = nil
        suggestion_product_id = nil

        if product_results.empty? && package_results.empty?
          best = Product.visible
                       .where(status: :active)
                       .select("products.*, word_similarity(#{ActiveRecord::Base.connection.quote(expanded)}, LOWER(products.title)) AS sim")
                       .order('sim DESC')
                       .limit(1)
                       .first
          if best && best.sim && best.sim > 0.3
            suggestion = best.title.truncate(50)
            suggestion_product_id = best.id
          end
        end

        # Merge, sort, paginate
        merged = product_results.with_score.map { |r, score| format_result(r).merge(score: score || 0.0) } +
                 package_results.with_score.map { |r, score| format_result(r).merge(score: score || 0.0) }
        merged.compact!

        merged = apply_attribute_filters(merged)

        case sort
        when 'price_asc'
          merged.sort_by! { |r| r[:effective_price] || r[:price] || 0.0 }
        when 'price_desc'
          merged.sort_by! { |r| -(r[:effective_price] || r[:price] || 0.0) }
        when 'newest'
          merged.sort_by! { |r| -(r[:created_at].to_i) rescue 0 }
        when 'trending'
          # ★ Smart trending sort uses trending_score
          merged.sort_by! { |r| -(r[:trending_score] || 0.0) }
        when 'best_sellers'
          merged.sort_by! { |r| -(r[:sold_count] || 0) }
        when 'rating'
          merged.sort_by! { |r| -(r[:rating] || 0.0) }
        else
          merged.sort_by! { |r| -r[:score] }
        end

        total_count = product_results.total_count + package_results.total_count rescue merged.size
        offset = (page - 1) * per_page
        paged_results = merged[offset, per_page] || []

        # Sponsored section
        sponsored_products = begin
          Product.visible
                 .where(status: :active, sponsored: true)
                 .search(expanded, where: where.merge(sponsored: true), limit: 3, execute: false)
                 .results
        rescue
          []
        end

        # Featured section
        featured_products = begin
          Product.visible
                 .where(status: :active, featured: true)
                 .search(expanded, where: where.merge(featured: true), limit: 5, execute: false)
                 .results
        rescue
          []
        end

        product_ids = product_results.map(&:id) rescue []
        package_ids = package_results.map(&:id) rescue []

        brands = Product.where(id: product_ids).where.not("product_attributes->>'brand' IS NULL")
                        .pluck(Arel.sql("DISTINCT product_attributes->>'brand'")).compact.uniq.first(20)

        cat_ids_prod = Product.where(id: product_ids).pluck(:category_id).compact
        cat_ids_pkg  = Package.joins(:categories).where(id: package_ids).pluck('categories.id')
        all_cat_ids  = (cat_ids_prod + cat_ids_pkg).uniq
        categories   = Category.where(id: all_cat_ids).select(:id, :name).map { |c| { id: c.id, name: c.name } }

        prices_prod = Product.where(id: product_ids).pluck(Arel.sql("COALESCE(price, 0)"))
        prices_pkg  = Package.where(id: package_ids).pluck(:price)
        all_prices  = prices_prod + prices_pkg
        price_min   = all_prices.min || 0
        price_max   = all_prices.max || 10000

        keys = Product.where(id: product_ids).where.not(product_attributes: nil)
                     .pluck(Arel.sql("jsonb_object_keys(product_attributes)")).flatten.uniq.reject { |k| k == 'brand' }
        dynamic_attrs = {}
        keys.first(10).each do |key|
          values = Product.where(id: product_ids).where.not(product_attributes: nil)
                         .pluck(Arel.sql("product_attributes ->> '#{key}'")).compact.uniq.first(10)
          dynamic_attrs[key] = values if values.any?
        end

        ratings = Product.where(id: product_ids).distinct.pluck(:rating).compact.sort.reverse

        # Delivery options using model's delivery_label logic
        delivery_options = Product.where(id: product_ids).map(&:delivery_label).uniq.sort

        discount_types = Package.where(id: package_ids).pluck(:discount_type).compact.uniq

        filters = {
          brands: brands,
          categories: categories,
          price_range: { min: price_min, max: price_max },
          attributes: dynamic_attrs,
          package_discount_types: discount_types,
          ratings: ratings,
          delivery_options: delivery_options
        }

        render json: {
          data: paged_results,
          meta: {
            current_page: page,
            next_page: (offset + per_page) < merged.size ? page + 1 : nil,
            total_count: total_count,
            per_page: per_page,
            dominant_category: compute_dominant_category(product_results, package_results)&.then { |c| { id: c.id, name: c.name } },
            filters: filters,
            suggestion: suggestion,
            suggestion_product_id: suggestion_product_id,
            sponsored: sponsored_products.map { |p| product_to_result(p).merge(sponsored: true) },
            featured: featured_products.map { |p| product_to_result(p).merge(featured: true) }
          }
        }
      end

      private

      def apply_attribute_filters(results)
        known_keys = %w[q page per_page sort category brand price_min price_max rating delivery controller action search]
        params.each do |key, value|
          next if known_keys.include?(key)
          next if value.blank?
          values = value.to_s.split(',').map(&:strip).map(&:downcase)
          results = results.select do |item|
            next true unless item[:type] == 'product'
            attrs = item[:product_attributes] || {}
            attr_value = attrs[key]&.to_s&.downcase
            values.include?(attr_value)
          end
        end
        results
      end

      def product_to_result(p)
        vendor = p.vendor
        {
          type: 'product',
          id: p.id,
          title: p.title,
          description: p.description,
          price: p.price,
          effective_price: p.effective_selling_price,
          rating: p.rating,
          reviews_count: p.reviews_count,
          sold_count: p.sold_count,
          free_shipping: p.free_shipping,
          discount: p.discount_percentage,
          stock: p.stock,
          available_stock: p.available_stock,
          status: p.status,
          featured: p.featured,
          sponsored: p.sponsored,
          views_count: p.views_count,
          trending_score: p.trending_score,
          is_flash_sale: p.is_flash_sale,
          flash_sale_price: p.flash_sale_price,
          flash_sale_ends_at: p.flash_sale_ends_at,
          is_super_deal: p.is_super_deal,
          super_deal_price: p.super_deal_price,
          super_deal_ends_at: p.super_deal_ends_at,
          delivery_label: p.delivery_label,
          category: p.category ? { id: p.category.id, name: p.category.name } : nil,
          vendor: vendor ? {
            id: vendor.id,
            business_name: vendor.business_name,
            membership_tier: vendor.membership_tier,
            badge: vendor.display_badge,
            rating: vendor.average_rating,
            total_sales: vendor.total_sales_count,
            products_count: vendor.products_count
          } : nil,
          image_urls: p.image_urls,
          product_attributes: p.product_attributes || {},
          variants: p.variants_data || [],
          seller_pays_shipping: p.seller_pays_shipping,
          score: 0.0,
          created_at: p.created_at,
          bulk_enabled: p.bulk_enabled?,
          out_of_stock: p.out_of_stock?,
          orderable: p.can_be_ordered?(1)
        }
      end

      def build_filters_for(products)
        ids = products.pluck(:id)
        brands = Product.where(id: ids).where.not("product_attributes->>'brand' IS NULL")
                        .pluck(Arel.sql("DISTINCT product_attributes->>'brand'")).compact.uniq.first(20)
        cat_ids = Product.where(id: ids).pluck(:category_id).compact.uniq
        cats = Category.where(id: cat_ids).select(:id, :name).map { |c| { id: c.id, name: c.name } }
        prices = Product.where(id: ids).pluck(Arel.sql("COALESCE(price, 0)"))
        { brands: brands, categories: cats, price_range: { min: prices.min || 0, max: prices.max || 10000 }, attributes: {}, package_discount_types: [], ratings: [], delivery_options: [] }
      end

      def format_result(record)
        if record.is_a?(Product)
          vendor = record.vendor
          {
            type: 'product', id: record.id, title: record.title, description: record.description,
            price: record.price, effective_price: record.effective_selling_price,
            rating: record.rating, reviews_count: record.reviews_count,
            sold_count: record.sold_count, free_shipping: record.free_shipping,
            discount: record.discount_percentage, stock: record.stock,
            available_stock: record.available_stock,
            status: record.status, featured: record.featured, sponsored: record.sponsored,
            views_count: record.views_count, trending_score: record.trending_score,
            is_flash_sale: record.is_flash_sale, flash_sale_price: record.flash_sale_price,
            flash_sale_ends_at: record.flash_sale_ends_at, is_super_deal: record.is_super_deal,
            super_deal_price: record.super_deal_price, super_deal_ends_at: record.super_deal_ends_at,
            delivery_label: record.delivery_label,
            category: record.category ? { id: record.category.id, name: record.category.name } : nil,
            vendor: vendor ? {
              id: vendor.id, business_name: vendor.business_name,
              membership_tier: vendor.membership_tier, badge: vendor.display_badge,
              rating: vendor.average_rating, total_sales: vendor.total_sales_count,
              products_count: vendor.products_count
            } : nil,
            image_urls: record.image_urls, product_attributes: record.product_attributes || {},
            variants: record.variants_data || [], seller_pays_shipping: record.seller_pays_shipping,
            created_at: record.created_at,
            bulk_enabled: record.bulk_enabled?,
            out_of_stock: record.out_of_stock?,
            orderable: record.can_be_ordered?(1)
          }
        else
          # Package
          {
            type: 'package', id: record.id, title: record.name, description: record.description,
            price: record.price, original_price: record.original_price, discount_type: record.discount_type,
            discount_value: record.discount_value, items_count: record.products.count,
            status: record.status,
            trending_score: record.trending_score,
            vendor: record.vendor ? {
              id: record.vendor.id,
              business_name: record.vendor.business_name,
              badge: record.vendor.display_badge
            } : nil,
            image_urls: record.image_urls, seller_pays_shipping: record.seller_pays_shipping?,
            created_at: record.created_at
          }
        end
      end

      def compute_dominant_category(products, packages)
        cat_counts = Hash.new(0)
        products.each { |p| cat_counts[p.category_id] += 1 if p.try(:category_id) }
        packages.each { |pkg| pkg.categories.pluck(:id).each { |id| cat_counts[id] += 1 } }
        dominant_id = cat_counts.max_by { |_, count| count }&.first
        Category.find_by(id: dominant_id)
      end
    end
  end
end