# app/services/checkout_service.rb
class CheckoutService
  class CheckoutError < StandardError; end

  attr_reader :cart, :user, :address, :payment_method, :partner_name,
              :partner_id, :coupon_code, :delivery_speed, :errors, :orders

  def initialize(cart:, user:, address:, payment_method:,
                 partner_name: nil, partner_id: nil, coupon_code: nil,
                 idempotency_key: nil, delivery_speed: 0)
    @cart = cart
    @user = user
    @address = address
    @payment_method = payment_method
    @partner_name = partner_name
    @partner_id = partner_id
    @coupon_code = coupon_code
    @idempotency_key = idempotency_key
    @delivery_speed = delivery_speed.to_i
    @errors = []
    @orders = []
  end

  # ── Public class method for shipping options ─────────────
  def self.shipping_options(cart, address)
    vendor_items = cart.cart_items.includes(product: :vendor, package: :vendor)
                       .group_by { |item| item.product&.vendor || item.package&.vendor }
    vendors = vendor_items.keys.compact.uniq
    return [] if vendors.empty?

    buyer_lat = address.latitude&.to_f
    buyer_lng = address.longitude&.to_f
    return [] unless buyer_lat && buyer_lng

    total_weight = cart_total_weight(cart)
    fragile = cart_has_fragile_items?(cart)

    LogisticsPartner.active.map do |partner|
      raw_quote = calculate_consolidated_shipping(
        vendor_items, buyer_lat, buyer_lng, total_weight, partner,
        fragile: fragile, express: false
      )
      next unless raw_quote && raw_quote[:charge].present?

      breakdown = calculate_final_shipping_cost(
        cart, vendor_items, total_weight, raw_quote[:charge],
        fragile: fragile, express: false
      )

      label = case partner.delivery_speed.to_i
              when 1 then "Express"
              when 2 then "Next Day"
              else "Standard"
              end

      processing_hours = case partner.delivery_speed.to_i
                         when 2 then 1
                         when 1 then 1
                         else 2
                         end

      transit_minutes = raw_quote[:duration_minutes] || 0
      estimated_datetime = Time.current + processing_hours.hours + transit_minutes.minutes
      estimated_datetime = adjust_to_business_hours(estimated_datetime)

      today = Date.current
      est_date = estimated_datetime.to_date
      est_time = estimated_datetime.strftime("%I:%M %p")
      delivery_label_time = if est_date == today
                              "Today by #{est_time}"
                            elsif est_date == today + 1
                              "Tomorrow by #{est_time}"
                            else
                              estimated_datetime.strftime("%b %d, %I:%M %p")
                            end

      estimated_days = (est_date - today).to_i

      {
        partner_id: partner.id,
        delivery_label: label,
        estimated_days: estimated_days,
        estimated_delivery: estimated_datetime.iso8601,
        estimated_delivery_label: delivery_label_time,
        charge: breakdown[:final_buyer_shipping],
        raw_carrier_cost: raw_quote[:charge],
        seller_subsidy: breakdown[:total_subsidy],
        platform_markup: breakdown[:platform_markup],
        delivery_speed: partner.delivery_speed
      }
    end.compact
  end

  def call
    return false if cart.cart_items.empty?

    if @idempotency_key.present? && Order.exists?(idempotency_key: @idempotency_key)
      @errors << "Duplicate order detected."
      return false
    end

    if user.vendor.present?
      own_vendor_id = user.vendor.id
      if cart.cart_items.any? { |item| (item.product&.vendor_id || item.package&.vendor_id) == own_vendor_id }
        @errors << "You cannot purchase items from your own shop."
        return false
      end
    end

    # Bulk MOQ check
    cart.cart_items.each do |item|
      product = item.product
      next unless product&.bulk_enabled?
      moq = product.minimum_bulk_quantity || 1
      if item.quantity < moq
        @errors << "Wholesale product '#{product.title}' requires a minimum of #{moq} units."
        return false
      end
    end

    # Variant required check
    cart.cart_items.each do |item|
      next unless item.product
      if item.product.has_real_variants? && item.variant_attributes.blank?
        @errors << "Please select a variant for #{item.product.title}."
        return false
      end
    end

    # Order block windows
    block_start = Setting.get('order_block_start')
    block_end   = Setting.get('order_block_end')
    if block_start.present? && block_end.present?
      start_time = (Time.parse(block_start) rescue nil)
      end_time   = (Time.parse(block_end) rescue nil)
      if start_time && end_time && Time.current.between?(start_time, end_time)
        @errors << "Orders are temporarily paused."
        return false
      end
    end

    daily_start = Setting.get('daily_order_block_start')
    daily_end   = Setting.get('daily_order_block_end')
    if daily_start.present? && daily_end.present?
      current_time = Time.current.strftime("%H:%M")
      if daily_start < daily_end
        if current_time >= daily_start && current_time <= daily_end
          @errors << "Orders are paused during daily maintenance hours."
          return false
        end
      else
        if current_time >= daily_start || current_time <= daily_end
          @errors << "Orders are paused during daily maintenance hours."
          return false
        end
      end
    end

    vendors = cart.cart_items.map { |item| item.product&.vendor || item.package&.vendor }.compact.uniq
    vendors.each do |v|
      unless v.accepting_orders?
        @errors << "#{v.business_name} is not accepting orders."
        return false
      end
      unless v.status == 'approved'
        @errors << "#{v.business_name} is not an approved seller."
        return false
      end
    end

    # Location availability
    locations_setting = Setting.get('locations') || {}
    allowed = locations_setting['available_locations']
    if allowed.present?
      regions = allowed.split(',').map(&:strip).map(&:downcase)
      addr = address.full_address.to_s.downcase
      unless regions.any? { |r| addr.include?(r) }
        @errors << "We don't currently serve your area."
        return false
      end
    end

    partner = nil
    if @partner_id.present?
      partner = LogisticsPartner.active.find_by(id: @partner_id)
    elsif @partner_name.present?
      partner = LogisticsPartner.active.find_by(name: @partner_name)
    end
    if @partner_id.present? || @partner_name.present?
      if partner.nil?
        @errors << "Selected delivery option is not available"
        return false
      end
    end

    coupon = nil
    if coupon_code.present?
      coupon = Coupon.find_by(code: coupon_code.strip.upcase)
      if coupon.nil?
        @errors << "Invalid coupon code"
        return false
      end
      unless coupon.valid_for?(user, cart.total_price)
        @errors << "Coupon cannot be applied to this order"
        return false
      end
    end

    buyer_lat = address.latitude&.to_f
    buyer_lng = address.longitude&.to_f
    if partner && (!buyer_lat || !buyer_lng)
      @errors << "Address coordinates missing"
      return false
    end

    items_by_vendor = cart.cart_items.group_by { |item| item.product&.vendor || item.package&.vendor }
    total_weight = self.class.cart_total_weight(cart)
    fragile = self.class.cart_has_fragile_items?(cart)

    if partner
      raw_quote = self.class.calculate_consolidated_shipping(
        items_by_vendor,
        buyer_lat,
        buyer_lng,
        total_weight,
        partner,
        fragile: fragile,
        express: delivery_speed > 0
      )
      if raw_quote.nil? || raw_quote[:charge].nil?
        @errors << "Unable to calculate shipping quote."
        return false
      end

      breakdown = self.class.calculate_final_shipping_cost(
        cart, items_by_vendor, total_weight, raw_quote[:charge],
        fragile: fragile, express: delivery_speed > 0
      )
      carrier_cost = raw_quote[:charge]
      final_buyer_shipping = breakdown[:final_buyer_shipping]
      total_subsidy = breakdown[:total_subsidy]
      platform_markup = breakdown[:platform_markup]
    else
      carrier_cost = 0
      final_buyer_shipping = 0
      total_subsidy = 0
      platform_markup = 0
    end

    vendor_shipping_split = self.class.shipping_split(items_by_vendor, total_weight, final_buyer_shipping)

    begin
      ActiveRecord::Base.transaction do
        checkout_group = CheckoutGroup.create!(
          user: user,
          consolidated_shipping_cost: carrier_cost,
          buyer_shipping_cost: final_buyer_shipping,
          total_subsidy: total_subsidy,
          platform_markup: platform_markup,
          status: :pending
        )

        product_ids = []
        package_ids = []
        cart.cart_items.each do |item|
          product_ids << item.product_id if item.product_id
          package_ids << item.package_id if item.package_id
          if item.package_id
            item.package.package_products.each { |pp| product_ids << pp.product_id }
          end
        end
        product_ids = product_ids.uniq
        package_ids = package_ids.uniq

        products_locked = Product.where(id: product_ids).lock("FOR UPDATE NOWAIT").index_by(&:id)
        packages_locked = Package.where(id: package_ids).lock("FOR UPDATE NOWAIT").index_by(&:id)

        first_order_id = nil
        items_by_vendor.each do |vendor, items|
          order = build_order(vendor, items, coupon, checkout_group.id, vendor_shipping_split[vendor.id])

          if @idempotency_key.present? && first_order_id.nil?
            order.idempotency_key = @idempotency_key
            first_order_id = :set
          end

          items.each do |cart_item|
            if cart_item.product
              product = products_locked[cart_item.product_id]
              raise CheckoutError, "Product not found" unless product

              if product.max_quantity_per_day.present?
                sold_today = product.today_quantity_sold
                if sold_today + cart_item.quantity > product.max_quantity_per_day
                  raise CheckoutError, "Daily quantity limit reached for '#{product.title}'."
                end
              end

              unless product.can_fulfill?(cart_item.quantity, variant: cart_item.variant_attributes.presence || nil)
                raise CheckoutError, "Insufficient stock for #{product.title}"
              end

              # Convert reservation to sale
              if cart_item.variant_attributes.present? && product.variant_product?
                variant = product.find_variant(cart_item.variant_attributes)
                raise CheckoutError, "Variant not found" unless variant
                unless variant.unlimited_stock?
                  variant.update_column(:stock, variant.stock - cart_item.quantity)
                  variant.update_column(:reserved, [variant.reserved - cart_item.quantity, 0].max)
                end
              else
                unless product.bulk_enabled? && product.stock.nil?
                  product.update_column(:stock, product.stock - cart_item.quantity)
                  product.update_column(:stock_reserved, [product.stock_reserved - cart_item.quantity, 0].max)
                end
              end

              product.increment!(:sold_count, cart_item.quantity) rescue nil
            elsif cart_item.package
              package = packages_locked[cart_item.package_id]
              raise CheckoutError, "Package not found" unless package
              raise CheckoutError, "Insufficient stock for #{package.name}" if package.out_of_stock? || (package.available_stock != Float::INFINITY && package.available_stock < cart_item.quantity)

              unless package.bulk_enabled? && package.stock.nil?
                package.update_column(:stock, package.stock - cart_item.quantity)
                package.update_column(:stock_reserved, [package.stock_reserved - cart_item.quantity, 0].max)
              end

              package.package_products.each do |pp|
                pr = products_locked[pp.product_id]
                raise CheckoutError, "Product inside package not found" unless pr
                qty = cart_item.quantity

                if pp.variant_attributes.present? && pr.variant_product?
                  variant = pr.find_variant(pp.variant_attributes)
                  raise CheckoutError, "Variant not found for #{pr.title}" unless variant
                  unless variant.unlimited_stock?
                    raise CheckoutError, "Insufficient variant stock for #{pr.title}" if variant.stock < qty
                    variant.update_column(:stock, variant.stock - qty)
                    variant.update_column(:reserved, [variant.reserved - qty, 0].max)
                  end
                else
                  unless pr.bulk_enabled? && pr.stock.nil?
                    raise CheckoutError, "Insufficient stock for #{pr.title}" if pr.stock < qty
                    pr.update_column(:stock, pr.stock - qty)
                    pr.update_column(:stock_reserved, [pr.stock_reserved - qty, 0].max)
                  end
                end

                pr.increment!(:sold_count, qty) rescue nil
              end
            end
          end

          order.save!
          # ★ FIX: Transition COD orders to pending_acceptance immediately
          if order.payment_cash_on_delivery? && order.status == 'pending'
            order.pay!
          end
          @orders << order
        end

        coupon&.mark_used!(user) if coupon.present?

        # Clear cart items WITHOUT releasing stock (reservations already converted)
        cart.clear_after_checkout!
      end

      # ★ IMPORTANT: Delivery requests are NOT created here anymore.
      # They are created by Seller::OrdersController#accept after seller accepts the order.
      # This prevents duplicate delivery requests.

    rescue CheckoutService::CheckoutError => e
      @errors << e.message
      return false
    rescue ActiveRecord::LockWaitTimeout
      @errors << "Order could not be processed due to high demand. Please try again."
      return false
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      return false
    rescue ActiveRecord::Rollback => e
      @errors << e.message
      return false
    end

    @orders.any? ? @orders : false
  end

  private

  # ── Helper class methods ────────────────────────────

  def self.cart_total_weight(cart)
    total = cart.cart_items.sum do |item|
      if item.product
        (item.product.weight_kg || 1.0) * item.quantity
      elsif item.package
        item.package.products.sum { |p| p.weight_kg || 1.0 } * item.quantity
      else
        1.0 * item.quantity
      end
    end
    total <= 0 ? 1.0 : total
  end

  def self.cart_has_fragile_items?(cart)
    cart.cart_items.any? { |item| item.product&.product_attributes&.dig('fragile').to_s.downcase == 'true' }
  end

  def self.calculate_final_shipping_cost(cart, items_by_vendor, total_weight, raw_carrier_cost, fragile: false, express: false)
    total_subsidy = 0.0

    if raw_carrier_cost > 0
      items_by_vendor.each do |vendor, items|
        vendor_weight = items.sum do |item|
          if item.product
            (item.product.weight_kg || 1.0) * item.quantity
          elsif item.package
            item.package.products.sum { |p| p.weight_kg || 1.0 } * item.quantity
          else
            1.0 * item.quantity
          end
        end
        next if vendor_weight.zero? || total_weight.zero?
        vendor_share = raw_carrier_cost * (vendor_weight / total_weight)

        items.each do |item|
          if item.product
            product = item.product
            if product.seller_pays_shipping?
              item_weight = (product.weight_kg || 1.0) * item.quantity
              item_share = vendor_share * (item_weight / vendor_weight) rescue 0
              case product.shipping_subsidy_type
              when 'full'    then total_subsidy += item_share
              when 'percent' then total_subsidy += item_share * (product.shipping_subsidy_value / 100.0)
              when 'fixed'   then total_subsidy += [product.shipping_subsidy_value, item_share].min
              end
            end
          elsif item.package
            package = item.package
            if package.seller_pays_shipping?
              item_weight = package.products.sum { |p| p.weight_kg || 1.0 } * item.quantity
              item_share = vendor_share * (item_weight / vendor_weight) rescue 0
              case package.shipping_subsidy_type
              when 'full'    then total_subsidy += item_share
              when 'percent' then total_subsidy += item_share * (package.shipping_subsidy_value / 100.0)
              when 'fixed'   then total_subsidy += [package.shipping_subsidy_value, item_share].min
              end
            end
          end
        end
      end
    end

    buyer_shipping_cost = [raw_carrier_cost - total_subsidy, 0].max
    markup_rate = (Setting.get('shipping_markup_percent') || 0).to_f / 100.0
    platform_markup = raw_carrier_cost * markup_rate
    final_buyer_shipping = buyer_shipping_cost + platform_markup

    {
      total_subsidy: total_subsidy.round(2),
      buyer_shipping_cost: buyer_shipping_cost.round(2),
      platform_markup: platform_markup.round(2),
      final_buyer_shipping: final_buyer_shipping.round(2)
    }
  end

  def self.calculate_consolidated_shipping(items_by_vendor, buyer_lat, buyer_lng, total_weight, partner, fragile: false, express: false)
    return nil unless buyer_lat && buyer_lng

    vendors = items_by_vendor.keys
    pickup_points = vendors.map { |v| [v.business_lat, v.business_lng] }.compact
    return nil if pickup_points.empty?

    origin = pickup_points.first
    waypoints = pickup_points[1..-1]
    destination = [buyer_lat, buyer_lng]

    route = GebetaMapsService.route(origin: origin, destination: destination, waypoints: waypoints)

    if route
      total_distance_km = route[:distance_km]
      total_duration_minutes = route[:duration_minutes]
    else
      distances = pickup_points.map { |(lat, lng)| GebetaMapsService.haversine_distance(lat, lng, buyer_lat, buyer_lng) * 1.3 }
      total_distance_km = distances.sum
      extra_stops = [vendors.size - 1, 0].max
      if extra_stops > 0
        avg_distance_to_buyer = distances.sum / distances.size
        total_distance_km += extra_stops * avg_distance_to_buyer * 0.4
      end
      total_duration_minutes = (total_distance_km / 30.0 * 60.0).round
    end

    extra_stops = [vendors.size - 1, 0].max
    vehicle_type = vehicle_type_for_weight(total_weight)
    rate_card = partner.rate_cards.find_by(vehicle_type: vehicle_type)

    if rate_card
      base = rate_card.base_rate.to_f
      per_km = rate_card.per_km_rate.to_f
      min_charge = rate_card.min_charge.to_f
      weight_surcharge = rate_card.weight_surcharge_per_kg_above_5kg.to_f
      express_surcharge = rate_card.express_surcharge_percent.to_f
      fragile_surcharge = rate_card.fragile_surcharge.to_f
    else
      base = partner.base_rate.to_f
      per_km = partner.per_km_rate.to_f
      min_charge = partner.min_charge.to_f
      weight_surcharge = 0
      express_surcharge = 0
      fragile_surcharge = 0
    end

    cost = base + (total_distance_km * per_km)

    max_stop_fee = base * 0.3
    stop_fee = [extra_stops * base * 0.15, max_stop_fee].min
    cost += stop_fee

    if total_weight > 5
      cost += (total_weight - 5) * weight_surcharge
    end

    cost += cost * (express_surcharge / 100.0) if express
    cost += fragile_surcharge if fragile

    cost = [cost, min_charge].max

    total_duration_minutes += extra_stops * 5
    estimated_days = (total_duration_minutes / (8 * 60)).ceil
    estimated_days = 1 if estimated_days < 1

    {
      charge: cost.round(2),
      estimated_days: estimated_days,
      route_distance_km: total_distance_km.round(2),
      duration_minutes: total_duration_minutes.round
    }
  end

  def self.vehicle_type_for_weight(weight_kg)
    return 'truck' if weight_kg > 1000
    return 'van'   if weight_kg > 200
    return 'car'   if weight_kg > 20
    'motorcycle'
  end

  def self.business_hours
    defaults = Setting.get('logistics_defaults') || {}
    bh = defaults['business_hours'] || { 'start' => '08:00', 'end' => '20:00' }
    {
      start: (bh['start'] || '08:00'),
      end:   (bh['end']   || '20:00')
    }
  end

  def self.adjust_to_business_hours(time)
    bh = business_hours
    start_hour, start_min = bh[:start].split(':').map(&:to_i)
    end_hour, end_min = bh[:end].split(':').map(&:to_i)

    start_today = time.change(hour: start_hour, min: start_min, sec: 0)
    end_today   = time.change(hour: end_hour, min: end_min, sec: 0)

    if time < start_today
      time = start_today
    elsif time > end_today
      time = start_today + 1.day
    end
    time
  end

  def self.shipping_split(items_by_vendor, total_weight, total_shipping)
    split = {}
    items_by_vendor.each do |vendor, items|
      vendor_weight = items.sum do |item|
        if item.product
          (item.product.weight_kg || 1.0) * item.quantity
        elsif item.package
          item.package.products.sum { |p| p.weight_kg || 1.0 } * item.quantity
        else
          1.0 * item.quantity
        end
      end
      split[vendor.id] = total_weight.zero? ? 0 : (total_shipping * (vendor_weight / total_weight)).round(2)
    end
    split
  end

  def build_order(vendor, items, coupon, group_id, shipping_cost_amount)
    subtotal = items.sum do |item|
      if item.product
        (item.product.current_price || 0) * item.quantity
      elsif item.package
        (item.package.current_price || 0) * item.quantity
      else
        0
      end
    end

    discount = coupon.present? ? coupon.apply_to(subtotal) : 0

    fee_setting = Setting.get('tax_and_fees') || {}
    service_fee = 0.0
    if fee_setting['service_fee_type'] == 'percentage'
      service_fee = (subtotal * (fee_setting['service_fee_value'].to_f / 100)).round(2)
    elsif fee_setting['service_fee_type'] == 'flat'
      service_fee = fee_setting['service_fee_value'].to_f.round(2)
    end

    vat_rate = (fee_setting['vat_rate'] || 0).to_f / 100.0
    vat_amount = (service_fee * vat_rate).round(2)

    total = subtotal + service_fee + vat_amount - discount + shipping_cost_amount
    total = 0 if total < 0

    payment_enum = case payment_method
                   when 'telebirr', 'chapa', 'cash_on_delivery' then payment_method.to_sym
                   else :cash_on_delivery
                   end

    policy = ReturnPolicy.for_category(items.first&.product&.category_id) || ReturnPolicy.active.find_by(applicable_categories: [])

    order = Order.new(
      user: user,
      vendor: vendor,
      shipping_address: address.full_address,
      payment_method_enum: payment_enum,
      payment_status: :pending,
      status: :pending,
      shipping_cost: shipping_cost_amount,
      total: total,
      discount_amount: discount,
      service_fee: service_fee,
      vat_amount: vat_amount,
      checkout_group_id: group_id,
      return_window_days: policy&.return_window_days || 7,
      restocking_fee_percent: policy&.restocking_fee_percent || 0.0,
      return_shipping_responsibility: policy&.return_shipping_responsibility || 'buyer'
    )
    order.payment_method = payment_method

    total_commission = 0
    items.each do |cart_item|
      if cart_item.product
        product = cart_item.product
        unit_price = product.current_price || 0
        rate = product.effective_commission_rate || 0
        commission = (unit_price * cart_item.quantity * rate / 100.0).round(2)
        total_commission += commission
        order.line_items.build(
          product: product,
          quantity: cart_item.quantity,
          price: unit_price,
          commission_rate: rate,
          commission_amount: commission,
          variant_attributes: cart_item.variant_attributes.presence || {}
        )
      elsif cart_item.package
        package = cart_item.package
        unit_price = package.current_price || 0
        order.line_items.build(
          package_id: package.id,
          quantity: cart_item.quantity,
          price: unit_price,
          commission_rate: 0,
          commission_amount: 0
        )
      end
    end

    order.commission_amount = total_commission
    order
  end

  def requires_delivery?(order)
    order.line_items.any? { |li| li.product_id.present? || li.package_id.present? }
  end
end