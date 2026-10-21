# et_marketplace_backend/app/controllers/api/filters_controller.rb

class Api::FiltersController < ApplicationController
  allow_unauthenticated_access only: [:index]

  def index
    # Determine the category context
    if params[:category].present?
      current_category = Category.find(params[:category])
      category_ids = current_category.subtree_ids
      # For a main category page we return its direct children as "categories"
      categories = current_category.children.order(:name).map do |c|
        { id: c.id, name: c.name, image_url: c.try(:image_url) }
      end
    elsif params[:parent_category].present?
      parent_cat = Category.find(params[:parent_category])
      # Return direct children of the given parent
      categories = parent_cat.children.order(:name).map do |c|
        { id: c.id, name: c.name, image_url: c.try(:image_url) }
      end
      category_ids = parent_cat.subtree_ids
    else
      # Global – return top‑level categories
      categories = Category.where(parent_id: nil).order(:name).map do |c|
        { id: c.id, name: c.name, image_url: c.try(:image_url) }
      end
      category_ids = nil
    end

    # Base products scope, scoped to category_ids if present
    products = Product.where(status: :active)
    products = products.where(category_id: category_ids) if category_ids

    # ---- Structured attributes (for product form, not used by the filter UI) ----
    structured_attributes = []
    if current_category
      current_category.category_attributes.includes(:attr).each do |ca|
        attr = ca.attr
        next unless attr
        structured_attributes << {
          id: attr.id,
          name: attr.name,
          display_name: attr.display_name,
          attr_type: attr.attr_type,
          is_filterable: attr.is_filterable,
          is_variant: attr.is_variant,
          is_required: ca.is_required,
          values: attr.attribute_values.pluck(:value)
        }
      end
    end

    # ---- Dynamic attributes (for filter sidebar) ----
    all_keys = products.where.not(product_attributes: nil)
                      .pluck(Arel.sql("jsonb_object_keys(product_attributes)"))
                      .flatten.uniq

    dynamic = {}
    all_keys.each do |key|
      raw_values = products.where.not(product_attributes: nil)
                           .where("product_attributes ? :key", key: key)
                           .pluck(Arel.sql("product_attributes->>'#{key}'"))
                           .compact
      next if raw_values.empty?

      normalized = raw_values.group_by { |v| v.downcase.strip }
                             .transform_values { |arr| arr.max_by { |v| arr.count(v) } }
                             .values.uniq.sort

      dynamic[key] = normalized
    end

    # Merge predefined attribute values from category attributes
    if current_category
      current_category.category_attributes.includes(:attr).each do |ca|
        attr = ca.attr
        next unless attr
        predefined = attr.attribute_values.pluck(:value)
        if dynamic.key?(attr.name)
          dynamic[attr.name] = (dynamic[attr.name] | predefined).sort
        elsif predefined.any?
          dynamic[attr.name] = predefined.sort
        end
      end
    end

    # ---- Price range ----
    price_min = products.minimum(:price)&.floor || 0
    price_max = products.maximum(:price)&.ceil || 10000

    # ---- Available vendors ----
    vendor_ids = products.distinct.pluck(:vendor_id).compact
    vendors = Vendor.where(id: vendor_ids).map { |v| { id: v.id, name: v.business_name } }

    # ---- Available ratings ----
    ratings = products.distinct.pluck(:rating).compact.sort.reverse

    # ---- Available delivery options ----
    delivery_labels_sql = <<-SQL.squish
      CASE
        WHEN products.free_shipping = true THEN 'Free Shipping'
        WHEN products.seller_pays_shipping = true AND products.shipping_subsidy_type = 'percent'
          THEN CONCAT(COALESCE(products.shipping_subsidy_value, 0)::int, '% Off Shipping')
        WHEN products.seller_pays_shipping = true AND products.shipping_subsidy_type = 'fixed'
          THEN CONCAT('$', COALESCE(products.shipping_subsidy_value, 0), ' Off Shipping')
        WHEN products.seller_pays_shipping = true AND products.shipping_subsidy_type IS NOT NULL
          THEN 'Discounted Shipping'
        ELSE 'Paid Shipping'
      END
    SQL

    delivery_options = products
      .distinct
      .pluck(Arel.sql("#{delivery_labels_sql}"))
      .compact
      .sort

    render json: {
      categories: categories,                         # main or sub categories
      attributes: structured_attributes,
      dynamic: dynamic,
      brands: dynamic['brand'] || [],
      price_range: { min: price_min, max: price_max },
      vendors: vendors,
      ratings: ratings,
      delivery_options: delivery_options
    }
  end
end