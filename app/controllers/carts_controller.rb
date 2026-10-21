# app/controllers/carts_controller.rb

class CartsController < ApplicationController
  before_action :require_authentication
  before_action :set_cart, only: [:show, :add_item, :add_items, :update_item, :remove_item]
  before_action :release_expired_items, only: [:show, :add_item, :add_items, :update_item, :remove_item]

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from Product::InsufficientStockError, Package::InsufficientStockError, with: :insufficient_stock

  class StockLimitError < StandardError; end

  # GET /cart
  def show
    authorize @cart
    render json: cart_json(@cart)
  end

  # POST /cart/add_item
  def add_item
    checker = StockChecker.new(params)
    raise StockLimitError, checker.error unless checker.valid?

    ActiveRecord::Base.transaction do
      target = checker.target
      target.lock!

      raise StockLimitError, checker.error unless checker.still_available?

      cart_item = find_or_build_cart_item(checker)
      cart_item.save!
    end

    @cart.reload
    render json: cart_json(@cart)
  rescue StockLimitError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  # POST /cart/add_items – atomic batch add for multi‑variant products
  def add_items
    items_params = params.require(:items)
    raise ArgumentError, "At least one item required" if items_params.blank?

    ActiveRecord::Base.transaction do
      # Build checkers and lock targets in a consistent order to prevent deadlocks
      checkers = items_params.map do |item|
        StockChecker.new(
          product_id: item[:product_id],
          package_id: item[:package_id],
          variant:   item[:variant],
          quantity:  item[:quantity].to_i
        ).tap do |checker|
          raise StockLimitError, "Item: #{checker.error}" unless checker.valid?
          checker.target.lock!
        end
      end

      # Precompute existing cart quantities per product for daily limit
      existing_qty_by_product = Hash.new(0)
      @cart.cart_items.where.not(product_id: nil).group(:product_id).sum(:quantity).each do |pid, qty|
        existing_qty_by_product[pid] = qty
      end

      new_qty_by_product = Hash.new(0)

      checkers.each do |c|
        next unless c.target.is_a?(Product)

        product = c.target
        # Daily limit check: sold_today + active_cart_qty + new_quantities <= max
        if product.max_quantity_per_day.present?
          sold_today = product.today_quantity_sold
          active_cart_qty = CartItem.joins(:cart)
                                    .where(product_id: product.id)
                                    .where("cart_items.expires_at > ?", Time.current)
                                    .sum(:quantity)

          new_qty_by_product[product.id] += c.quantity
          total_after = sold_today + active_cart_qty + new_qty_by_product[product.id]

          if total_after > product.max_quantity_per_day
            remaining = [product.max_quantity_per_day - sold_today - active_cart_qty, 0].max
            raise StockLimitError, "#{product.title} daily limit exceeded (only #{remaining} left today)"
          end
        end
      end

      checkers.each do |c|
        item = if c.target.is_a?(Product)
                 existing = @cart.cart_items.find_by(
                   product_id: c.target.id,
                   variant_attributes: c.variant_attrs
                 )
                 if existing
                   existing.quantity += c.quantity
                   existing.price = c.variant_attrs.present? ?
                     find_variant_price(c.target, c.variant_attrs) : c.target.current_price
                   existing.base_price = c.variant_attrs.present? ?
                     find_variant_base_price(c.target, c.variant_attrs) : c.target.price.to_f
                   existing
                 else
                   @cart.cart_items.build(
                     product_id: c.target.id,
                     variant_attributes: c.variant_attrs,
                     quantity: c.quantity,
                     price: c.variant_attrs.present? ?
                       find_variant_price(c.target, c.variant_attrs) : c.target.current_price,
                     base_price: c.variant_attrs.present? ?
                       find_variant_base_price(c.target, c.variant_attrs) : c.target.price.to_f
                   )
                 end
               else
                 existing = @cart.cart_items.find_by(package_id: c.target.id)
                 if existing
                   existing.quantity += c.quantity
                   existing.price = c.target.current_price
                   existing.base_price = c.target.price.to_f
                   existing
                 else
                   @cart.cart_items.build(
                     package_id: c.target.id,
                     quantity: c.quantity,
                     price: c.target.current_price,
                     base_price: c.target.price.to_f
                   )
                 end
               end

        item.save!
      end

      render json: cart_json(@cart.reload)
    end
  rescue StockLimitError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PATCH /cart/update_item
  def update_item
    cart_item = @cart.cart_items.find(params[:item_id])
    new_qty = params[:quantity].to_i
    return render json: { error: "Quantity must be positive" }, status: :unprocessable_entity if new_qty <= 0

    product = cart_item.product
    pkg = cart_item.package

    if product
      checker = StockChecker.new(product_id: product.id, variant: cart_item.variant_attributes, quantity: new_qty)
    elsif pkg
      checker = StockChecker.new(package_id: pkg.id, quantity: new_qty)
    else
      return render json: { error: "Invalid cart item" }, status: :unprocessable_entity
    end

    raise StockLimitError, checker.error unless checker.valid?

    ActiveRecord::Base.transaction do
      target = checker.target
      target.lock!

      raise StockLimitError, checker.error unless checker.still_available?

      cart_item.update!(quantity: new_qty)
    end

    @cart.reload
    render json: cart_json(@cart)
  rescue StockLimitError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  # DELETE /cart/remove_item/:id
  def remove_item
    cart_item = @cart.cart_items.find_by(id: params[:id])
    return render json: { error: "Item not found" }, status: :not_found unless cart_item

    product = cart_item.product
    bulk_moq = product&.bulk_enabled? && product&.minimum_bulk_quantity.present? ? product.minimum_bulk_quantity : nil
    notice = nil

    ActiveRecord::Base.transaction do
      cart_item.release_and_destroy!

      if bulk_moq.present?
        remaining_qty = @cart.cart_items.where(product_id: product.id).sum(:quantity)
        if remaining_qty > 0 && remaining_qty < bulk_moq
          @cart.cart_items.where(product_id: product.id).find_each(&:release_and_destroy!)
          notice = "All variants of #{product.title} were removed because the minimum order of #{bulk_moq} units was no longer met."
        end
      end
    end

    @cart.reload
    render json: cart_json(@cart).merge(notice ? { notice: notice } : {})
  end

  private

  def set_cart
    @cart = current_user.cart || current_user.create_cart
  end

  def release_expired_items
    @cart.release_expired_items! if @cart
  end

  # ── StockChecker ──
  class StockChecker
    attr_reader :error, :target, :variant_attrs, :quantity

    def initialize(params)
      @product_id   = params[:product_id]
      @package_id   = params[:package_id]
      @variant_attrs = permit_variant(params[:variant])
      @quantity     = (params[:quantity].to_i)
      @target       = nil
      @error        = nil

      if @quantity <= 0
        @error = "Quantity must be positive"
        return
      end

      find_target
      validate!
    end

    def valid?
      @error.nil?
    end

    def still_available?
      if @target.is_a?(Product)
        product = @target
        return false unless product.can_be_ordered?(@quantity)

        if @variant_attrs.present? && product.variant_product?
          variant = find_matching_variant(product, @variant_attrs)
          return false unless variant
          return true if variant.unlimited_stock?
          limit = variant.stock.to_i - variant.reserved.to_i
          return limit >= @quantity
        else
          return true if product.available_stock == Float::INFINITY
          return product.available_stock >= @quantity
        end
      elsif @target.is_a?(Package)
        package = @target
        return false if package.out_of_stock?
        return true if package.available_stock == Float::INFINITY
        return package.available_stock >= @quantity &&
               package.package_products.all? { |pp|
                 product = pp.product
                 # Use variant-aware available stock
                 if pp.variant_attributes.present? && product.variant_product?
                   variant = find_matching_variant(product, pp.variant_attributes)
                   variant.present? && (variant.unlimited_stock? || (variant.stock.to_i - variant.reserved.to_i) >= @quantity)
                 else
                   product.can_be_ordered?(@quantity) &&
                   (product.available_stock == Float::INFINITY || product.available_stock >= @quantity)
                 end
               }
      else
        false
      end
    rescue => e
      @error = e.message
      false
    end

    # Public class method for controller to avoid `send`
    def self.find_matching_variant(product, attrs)
      new(product_id: product.id, variant: attrs, quantity: 1).send(:find_matching_variant, product, attrs)
    end

    private

    def permit_variant(raw)
      return {} if raw.blank?
      raw = raw.to_unsafe_h rescue raw.to_h rescue {}
      raw.each_with_object({}) do |(k, v), h|
        if v.is_a?(String) || v.is_a?(Numeric) || v == true || v == false
          h[k] = v.to_s
        end
      end
    end

    def find_target
      if @product_id.present?
        @target = Product.find_by(id: @product_id)
        @error = "Product not found" unless @target
      elsif @package_id.present?
        @target = Package.find_by(id: @package_id)
        @error = "Package not found" unless @target
      else
        @error = "product_id or package_id required"
      end
    end

    def validate!
      return if @error

      if @target.is_a?(Product)
        product = @target

        if product.has_real_variants? && @variant_attrs.blank?
          @error = "Please select a variant"
          return
        end

        if product.max_quantity_per_day.present?
          sold_today = product.today_quantity_sold
          active_cart_qty = CartItem.joins(:cart)
                                    .where(product_id: product.id)
                                    .where("cart_items.expires_at > ?", Time.current)
                                    .sum(:quantity)
          if sold_today + active_cart_qty + @quantity > product.max_quantity_per_day
            remaining = [product.max_quantity_per_day - sold_today - active_cart_qty, 0].max
            @error = "Daily limit reached – only #{remaining} left today"
            return
          end
        end

        unless still_available?
          @error = stock_limit_error(product, @variant_attrs)
        end
      elsif @target.is_a?(Package)
        unless still_available?
          @error = "Only #{@target.available_stock.to_i} package(s) available"
        end
      end
    end

    def stock_limit_error(product, variant_attrs)
      limit = if variant_attrs.present? && product.variant_product?
                variant = find_matching_variant(product, variant_attrs)
                variant ? variant.stock.to_i - variant.reserved.to_i : 0
              else
                product.available_stock == Float::INFINITY ? nil : product.available_stock
              end
      if limit.nil? || limit == Float::INFINITY
        "#{product.title} is available"
      elsif limit == 0
        "#{product.title} is out of stock"
      else
        "Only #{limit} of #{product.title} available"
      end
    end

    def find_matching_variant(product, attrs)
      return nil if attrs.blank? || product.product_variants.empty?
      normalized_attrs = attrs.to_h.transform_keys { |k| k.to_s.strip.downcase }
                                    .transform_values { |v| v.to_s.strip.downcase }
      product.product_variants.find do |v|
        v_attrs = v.variant_attributes_hash
                     .transform_keys { |k| k.to_s.strip.downcase }
                     .transform_values { |v| v.to_s.strip.downcase }
        v_attrs == normalized_attrs
      end
    end
  end

  # ── Cart item builder (single item add, increments existing quantity) ──
  def find_or_build_cart_item(checker)
    if checker.target.is_a?(Product)
      existing = @cart.cart_items.find_by(
        product_id: checker.target.id,
        variant_attributes: checker.variant_attrs
      )
      if existing
        existing.quantity += checker.quantity
        existing.price = checker.variant_attrs.present? ?
                         find_variant_price(checker.target, checker.variant_attrs) : checker.target.current_price
        existing.base_price = checker.variant_attrs.present? ?
                         find_variant_base_price(checker.target, checker.variant_attrs) : checker.target.price.to_f
        existing
      else
        @cart.cart_items.build(
          product_id: checker.target.id,
          variant_attributes: checker.variant_attrs,
          quantity: checker.quantity,
          price: checker.variant_attrs.present? ?
                 find_variant_price(checker.target, checker.variant_attrs) : checker.target.current_price,
          base_price: checker.variant_attrs.present? ?
                 find_variant_base_price(checker.target, checker.variant_attrs) : checker.target.price.to_f
        )
      end
    else
      existing = @cart.cart_items.find_by(package_id: checker.target.id)
      if existing
        existing.quantity += checker.quantity
        existing.price = checker.target.current_price
        existing.base_price = checker.target.price.to_f
        existing
      else
        @cart.cart_items.build(
          package_id: checker.target.id,
          quantity: checker.quantity,
          price: checker.target.current_price,
          base_price: checker.target.price.to_f
        )
      end
    end
  end

  # ★ Returns the discounted variant price
  def find_variant_price(product, attrs)
    variant = StockChecker.find_matching_variant(product, attrs)
    if variant
      product.effective_price_for(variant.price.to_f)
    else
      product.current_price
    end
  end

  # ★ Returns the list (base) variant price
  def find_variant_base_price(product, attrs)
    variant = StockChecker.find_matching_variant(product, attrs)
    variant ? variant.price.to_f : product.price.to_f
  end

  # ── Cart JSON (includes base_price and original_price) ──
  def cart_json(cart)
    minimum_bulk_progress = {}
    cart.cart_items.includes(:product).each do |item|
      product = item.product
      next unless product&.bulk_enabled? && product.minimum_bulk_quantity.present?
      pid = product.id
      unless minimum_bulk_progress.key?(pid)
        total_qty = cart.cart_items.where(product_id: pid).sum(:quantity)
        met = total_qty >= product.minimum_bulk_quantity
        minimum_bulk_progress[pid] = {
          productId: pid,
          productTitle: product.title,
          minimumRequired: product.minimum_bulk_quantity,
          currentQuantity: total_qty,
          met: met,
          remaining: met ? 0 : product.minimum_bulk_quantity - total_qty
        }
      end
    end

    {
      id: cart.id,
      items: cart.cart_items.includes(:product, :package).map do |item|
        product = item.product
        pkg = item.package

        stock = if product
                  if item.variant_attributes.present?
                    variant = StockChecker.find_matching_variant(product, item.variant_attributes)
                    variant ? (variant.unlimited_stock? ? nil : [variant.stock.to_i - variant.reserved.to_i, 0].max) : nil
                  else
                    product.available_stock == Float::INFINITY ? nil : product.available_stock.to_i
                  end
                elsif pkg
                  pkg.available_stock == Float::INFINITY ? nil : pkg.available_stock.to_i
                end

        remaining_daily = nil
        if product && product.max_quantity_per_day.present?
          sold_today = product.today_quantity_sold
          active_cart_qty = CartItem.joins(:cart)
                                    .where(product_id: product.id)
                                    .where("cart_items.expires_at > ?", Time.current)
                                    .sum(:quantity)
          remaining_daily = [product.max_quantity_per_day - sold_today - active_cart_qty, 0].max
        end

        {
          id: item.id,
          productId: item.product_id,
          packageId: item.package_id,
          title: product&.title || pkg&.name,
          price: (item.price || 0).to_f,
          base_price: (item.base_price || 0).to_f,
          original_price: (item.base_price || 0).to_f,
          quantity: item.quantity,
          stock: stock,
          remainingDailyQuantity: remaining_daily,
          variant: item.variant_attributes.presence || {},
          image: product&.image_urls&.first || pkg&.image_urls&.first,
          bulkEnabled: product&.bulk_enabled? || false,
          minimumBulkQuantity: product&.minimum_bulk_quantity,
          maxQuantityPerDay: product&.max_quantity_per_day,
          expiresAt: item.expires_at&.iso8601,
          expiresInSeconds: item.expires_at ? [(item.expires_at - Time.current).to_i, 0].max : nil
        }
      end,
      minimumBulkProgress: minimum_bulk_progress,
      total: cart.total_price,
      item_count: cart.cart_items.sum(:quantity)
    }
  end

  def find_matching_variant(product, attrs)
    StockChecker.find_matching_variant(product, attrs)
  end

  def user_not_authorized
    render json: { error: 'You are not authorized to perform this action.' }, status: :forbidden
  end

  def insufficient_stock(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end
end