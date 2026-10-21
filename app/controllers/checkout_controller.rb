# app/controllers/checkout_controller.rb

class CheckoutController < ApplicationController
  before_action :require_authentication
  before_action :set_cart, only: [:create, :summary]
  before_action :set_address, only: [:create, :summary]
  before_action :release_expired_items, only: [:create, :summary]

  rescue_from Product::InsufficientStockError, Package::InsufficientStockError, with: :insufficient_stock

  # POST /checkout
  def create
    payment_method = params[:payment_method]
    idempotency_key = params[:idempotency_key] || SecureRandom.uuid

    service = CheckoutService.new(
      cart: @cart,
      user: current_user,
      address: @address,
      payment_method: payment_method,
      partner_name: params[:partner_name],
      partner_id: params[:partner_id],
      coupon_code: params[:coupon_code],
      idempotency_key: idempotency_key,
      delivery_speed: params[:delivery_speed] || 0
    )

    orders = service.call
    unless orders
      return render json: { errors: service.errors }, status: :unprocessable_entity
    end

    paid_orders = []
    failed_orders = []
    redirect_url = nil

    if payment_method.to_s == 'cash_on_delivery'
      orders.each { |o| o.pay! if o.may_pay? }
      paid_orders = orders
      # Clear cart immediately for COD – order is paid and stock is already converted.
      @cart.clear_after_checkout!
    else
      # Online payment – group payment via first order
      primary_order = orders.first
      grand_total = orders.sum(&:total)

      original_first_total = primary_order.total
      result = nil

      begin
        primary_order.update_column(:total, grand_total)
        result = PaymentService.process(order: primary_order)
      rescue => e
        result = { error: e.message }
      ensure
        primary_order.update_column(:total, original_first_total) if primary_order.total != original_first_total
      end

      if result[:redirect_url]
        redirect_url = result[:redirect_url]
        payment_txn = result[:prepay_id] || result[:transaction_id]
        primary_order.update_column(:payment_transaction_id, payment_txn) if payment_txn.present?
        paid_orders = orders
        # Clear cart after redirect initiation – order is placed, payment pending.
        @cart.clear_after_checkout!
      elsif result[:success]
        orders.each { |o| o.pay! if o.may_pay? }
        paid_orders = orders
        # Clear cart after successful online payment.
        @cart.clear_after_checkout!
      else
        orders.each do |o|
          o.cancel! if o.may_cancel?
        end
        failed_orders = orders.map { |o| { order_id: o.id, vendor: o.vendor.business_name, error: result[:error] } }
        # Do NOT clear cart – payment failed, user may retry.
      end
    end

    if redirect_url.nil? && failed_orders.empty? && paid_orders.any?
      paid_orders.each do |order|
        NotificationService.notify(current_user, "order_placed", { order_id: order.id, total: order.total })
        OrderMailer.order_confirmation(order).deliver_later

        order.line_items.each do |item|
          vendor = item.product&.vendor || item.package&.vendor
          next unless vendor
          NotificationService.notify(vendor.user, "new_order", { order_id: order.id, product_name: item.product&.title || item.package&.name })
        end
      end
    end

    if paid_orders.any?
      paid_orders.each do |order|
        next unless order.respond_to?(:requires_delivery?) ? order.requires_delivery? : true
        begin
          AssignmentService.create_delivery_request(order)
        rescue => e
          Rails.logger.error "[Checkout] Failed to create delivery request for Order ##{order.id}: #{e.message}"
        end
      end
    end

    checkout_group = orders.first.checkout_group
    response_data = {
      orders: orders.map { |o| order_json(o) },
      consolidated_shipping: checkout_group&.buyer_shipping_cost.to_f
    }

    if redirect_url
      response_data[:message] = "Redirecting to payment gateway"
      response_data[:redirect_url] = redirect_url
      status = :created
    elsif failed_orders.empty?
      response_data[:message] = "All orders placed successfully"
      status = :created
    elsif paid_orders.any?
      response_data[:message] = "Some orders could not be processed"
      response_data[:successful] = paid_orders.map { |o| order_json(o) }
      response_data[:failed] = failed_orders
      status = :multi_status
    else
      response_data = { error: "All payments failed", details: failed_orders }
      status = :unprocessable_entity
    end

    render json: response_data, status: status
  end

  # POST /checkout/summary
  # Returns a pre‑order summary with final shipping (subsidies applied)
  def summary
    summary_data = build_summary
    render json: summary_data
  rescue => e
    Rails.logger.error "Checkout summary error: #{e.message}"
    render json: { error: 'Unable to calculate summary' }, status: :unprocessable_entity
  end

  # POST /checkout/shipping_options
  def shipping_options
    address = current_user.addresses.find_by(id: params[:address_id])
    return render json: { error: "Address not found" }, status: :not_found unless address

    cart = current_user.cart
    return render json: { error: "Cart is empty" }, status: :unprocessable_entity if cart.nil? || cart.cart_items.empty?

    options = CheckoutService.shipping_options(cart, address)
    render json: options
  end

  # GET /checkout/payment_options
  def payment_options
    gateways = PaymentGateway.active.map do |g|
      { id: g.id, provider: g.provider, name: g.name }
    end
    render json: gateways
  end

  # POST /validate_coupon
  def validate_coupon
    code = params[:coupon_code].to_s.strip.upcase
    cart = current_user.cart
    subtotal = cart&.cart_items&.sum { |item| (item.price || 0) * item.quantity } || 0.0

    coupon = Coupon.find_by(code: code)
    if coupon && coupon.valid_for?(current_user, subtotal)
      discount = coupon.apply_to(subtotal).round(2)
      render json: { valid: true, code: coupon.code, discount: discount, message: "Coupon applied" }
    else
      render json: { valid: false, discount: 0, error: "Invalid or expired coupon" }, status: :unprocessable_entity
    end
  end

  private

  def set_cart
    @cart = current_user.cart
    if @cart.nil? || @cart.cart_items.empty?
      render json: { error: "Cart is empty" }, status: :unprocessable_entity
    end
  end

  def release_expired_items
    @cart.release_expired_items! if @cart
  end

  def set_address
    @address = current_user.addresses.find(params[:address_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Address not found" }, status: :not_found
  end

  def build_summary
    cart = @cart
    address = @address

    subtotal = cart.cart_items.sum { |item| (item.price || 0) * item.quantity }

    discount = 0.0
    if params[:coupon_code].present?
      coupon = Coupon.find_by(code: params[:coupon_code].to_s.strip.upcase)
      if coupon && coupon.valid_for?(current_user, subtotal)
        discount = coupon.apply_to(subtotal)
      end
    end

    options = CheckoutService.shipping_options(cart, address)
    selected = options.find { |opt| opt[:partner_id].to_i == params[:partner_id].to_i } || options.first

    shipping_charge = selected ? selected[:charge].to_f : 0.0

    service_fee = 0.0
    vat_amount = 0.0
    fee_setting = Setting.get('tax_and_fees') || {}
    if fee_setting['service_fee_type'] == 'percentage'
      service_fee = (subtotal * (fee_setting['service_fee_value'].to_f / 100)).round(2)
    elsif fee_setting['service_fee_type'] == 'flat'
      service_fee = fee_setting['service_fee_value'].to_f.round(2)
    end
    vat_rate = (fee_setting['vat_rate'] || 0).to_f / 100.0
    vat_amount = (service_fee * vat_rate).round(2)

    total = subtotal + service_fee + vat_amount - discount + shipping_charge
    total = 0 if total < 0

    result = {
      subtotal: subtotal.round(2),
      discount: discount.round(2),
      shipping: shipping_charge.round(2),
      service_fee: service_fee.round(2),
      vat: vat_amount.round(2),
      total: total.round(2),
      selected_shipping_option: selected,
      address: address_json(address),
      items: cart.cart_items.includes(:product, :package).map { |item| summary_item_json(item) }
    }

    if selected
      result[:raw_carrier_cost] = selected[:raw_carrier_cost].to_f
      result[:seller_subsidy] = selected[:seller_subsidy].to_f
      result[:platform_markup] = selected[:platform_markup].to_f
      result[:delivery] = {
        partner_name: selected[:partner_name],
        delivery_label: selected[:delivery_label],
        estimated_days: selected[:estimated_days],
        estimated_delivery_label: selected[:estimated_delivery_label]
      }.compact
    else
      result[:raw_carrier_cost] = 0.0
      result[:seller_subsidy] = 0.0
      result[:platform_markup] = 0.0
      result[:delivery] = {}
    end

    result
  end

  def address_json(addr)
    {
      id: addr.id,
      full_address: addr.full_address.presence || addr.address_line.presence || '',
      street: addr.respond_to?(:street) ? addr.street : nil,
      sub_city: addr.respond_to?(:sub_city) ? addr.sub_city : nil,
      woreda: addr.respond_to?(:woreda_text) ? addr.woreda_text : nil,
      city: addr.respond_to?(:city) ? addr.city : nil,
      landmark: addr.respond_to?(:landmark) ? addr.landmark : nil,
      neighborhood: addr.respond_to?(:neighborhood) ? addr.neighborhood : nil,
      phone: addr.phone,
      delivery_notes: addr.respond_to?(:delivery_notes) ? addr.delivery_notes : nil,
      latitude: addr.latitude,
      longitude: addr.longitude
    }.compact
  end

  def summary_item_json(item)
    product = item.product
    package = item.package
    title = product&.title || package&.name || "Item ##{item.id}"
    image = product&.first_image_url || package&.image_urls&.first
    vendor = product&.vendor || package&.vendor
    base = item.base_price.to_f
    price = item.price.to_f
    qty = item.quantity
    line_total = price * qty
    discount_total = [(base - price) * qty, 0].max.round(2)

    {
      cart_item_id: item.id,
      type: product ? 'product' : 'package',
      product_id: item.product_id,
      package_id: item.package_id,
      title: title,
      image_url: image,
      vendor_id: vendor&.id,
      vendor_name: vendor&.business_name || vendor&.shop_name,
      variant_attributes: item.variant_attributes.presence || {},
      base_price: base.round(2),
      price: price.round(2),
      quantity: qty,
      line_total: line_total.round(2),
      discount_total: discount_total,
      bulk_enabled: product&.bulk_enabled? || false,
      minimum_bulk_quantity: product&.minimum_bulk_quantity
    }.compact
  end

  def order_json(order)
    group = order.checkout_group
    {
      id: order.id,
      total: order.total.to_f,
      shipping_cost: order.shipping_cost.to_f,
      consolidated_shipping: group&.buyer_shipping_cost.to_f,
      service_fee: order.service_fee.to_f,
      vat_amount: order.vat_amount.to_f,
      discount_amount: order.discount_amount.to_f,
      status: order.status,
      payment_status: order.payment_status,
      shipping_address: order.shipping_address,
      created_at: order.created_at,
      items: order.line_items.map do |item|
        {
          product_id: item.product_id,
          package_id: item.package_id,
          title: item.product&.title || item.package&.name,
          quantity: item.quantity,
          price: item.price.to_f
        }
      end
    }
  end

  def insufficient_stock(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end
end