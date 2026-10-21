# app/controllers/orders_controller.rb

class OrdersController < ApplicationController
  before_action :require_authentication
  before_action :set_order, only: [:show, :update, :invoice, :generate_public_token, :invoice_data, :invoice_pdf_data]

  helper_method :invoice_html

  # GET /orders
  def index
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i.clamp(1, 100)

    scope = policy_scope(Order)
              .includes(:checkout_group, :vendor,
                        delivery_requests: :logistics_partner,
                        line_items: [:product, :package])

    # Apply date filters
    begin
      if params[:start_date].present?
        start_date = Date.parse(params[:start_date]).beginning_of_day
        scope = scope.where('orders.created_at >= ?', start_date)
      end

      if params[:end_date].present?
        end_date = Date.parse(params[:end_date]).end_of_day
        scope = scope.where('orders.created_at <= ?', end_date)
      end
    rescue Date::Error
      return render json: { error: 'Invalid date format. Use YYYY-MM-DD.' }, status: :unprocessable_entity
    end

    orders = scope.order(created_at: :desc)
                  .limit(per_page)
                  .offset((page - 1) * per_page)
    total = scope.count

    render json: {
      data: orders.map { |o| order_json(o) },
      meta: {
        current_page: page,
        per_page: per_page,
        total_count: total,
        next_page: (page * per_page) < total ? page + 1 : nil,
        prev_page: page > 1 ? page - 1 : nil
      }
    }
  end

  # GET /orders/:id
  def show
    authorize @order
    render json: order_json(@order)
  end

  # PATCH/PUT /orders/:id
  # Only allow updating shipping address if order is still mutable.
  def update
    authorize @order

    if @order.status.in?(%w[shipped delivered completed cancelled returned])
      return render json: { error: "Order cannot be updated in its current state" }, status: :unprocessable_entity
    end

    if @order.update(order_params)
      render json: order_json(@order)
    else
      render json: { errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /orders/:id/invoice
  def invoice
    authorize @order
    respond_to do |format|
      format.html { render html: invoice_html(@order).html_safe }
      format.pdf do
        pdf = WickedPdf.new.pdf_from_string(
          invoice_html(@order),
          page_size: 'A4',
          footer: { center: "Page [page] of [topage]" }
        )
        send_data pdf,
                  filename: "invoice_#{@order.id}.pdf",
                  type: 'application/pdf',
                  disposition: 'attachment'
      end
    end
  end

  # GET /orders/:id/invoice_data (authenticated JSON endpoint)
  def invoice_data
    authorize @order
    render json: { html: invoice_html(@order) }
  end

  # GET /orders/:id/invoice_pdf_data (authenticated JSON endpoint – returns base64 PDF)
  def invoice_pdf_data
    authorize @order
    pdf = WickedPdf.new.pdf_from_string(
      invoice_html(@order),
      page_size: 'A4',
      footer: { center: "Page [page] of [topage]" }
    )
    render json: { pdf_base64: Base64.strict_encode64(pdf) }
  end

  # POST /orders/:id/generate_public_token
  def generate_public_token
    authorize @order
    @order.update!(public_invoice_token: SecureRandom.urlsafe_base64(32)) unless @order.public_invoice_token.present?
    render json: { token: @order.public_invoice_token }
  end

  private

  def set_order
    @order = Order.includes(:vendor, :checkout_group,
                            delivery_requests: :logistics_partner,
                            line_items: [:product, :package])
                  .find(params[:id])
  end

  def order_params
    params.require(:order).permit(:shipping_address)
  end

  # ── Order JSON (package‑safe, no double shipping) ──
  def order_json(order)
    group = order.checkout_group
    items = order.line_items # already preloaded via includes

    consolidated_shipping = group&.buyer_shipping_cost.to_f
    subtotal = items.sum { |li| (li.price || 0) * li.quantity }.to_f
    discount = order.discount_amount.to_f
    service_fee = order.service_fee.to_f
    vat = order.vat_amount.to_f
    shipping = order.shipping_cost.to_f

    # ★ FIX: do not add consolidated shipping again; order.total already includes its shipping portion
    grand_total = order.total.to_f

    return_deadline = nil
    if order.delivered_at && order.return_window_days
      return_deadline = order.delivered_at + order.return_window_days.days
    end

    active_return = order.return_requests.order(created_at: :desc).first

    json = {
      id: order.id,
      vendor_id: order.vendor_id,
      vendor_name: order.vendor.business_name,
      total: grand_total,
      subtotal: subtotal,
      shipping_cost: shipping,
      consolidated_shipping: consolidated_shipping,
      service_fee: service_fee,
      vat_amount: vat,
      discount_amount: discount,
      status: order.status,
      payment_status: order.payment_status,
      payment_method_enum: order.payment_method_enum,
      shipping_address: order.shipping_address,
      payment_method: order.payment_method_enum,
      commission_amount: order.commission_amount.to_f,
      commission_rate: order.commission_rate.to_f,
      created_at: order.created_at,
      estimated_delivery: estimated_delivery(order),
      acceptance_deadline: order.acceptance_deadline,
      accepted_at: order.accepted_at,
      return_window_days: order.return_window_days,
      restocking_fee_percent: order.restocking_fee_percent,
      return_shipping_responsibility: order.return_shipping_responsibility,
      return_deadline: return_deadline,
      active_return_request: active_return ? { id: active_return.id, status: active_return.status } : nil,
      items: items.map do |item|
        product = item.product
        package = item.package
        title = product&.title || package&.name || "Item ##{item.id}"
        image = if product&.first_image_url
                  product.first_image_url
                elsif package && package.image_urls.is_a?(Array) && package.image_urls.any?
                  package.image_urls.first
                end

        {
          id: item.id,
          product_id: item.product_id,
          package_id: item.package_id,
          title: title,
          quantity: item.quantity,
          price: item.price.to_f,
          image: image,
          variant_attributes: item.variant_attributes.presence || {}
        }
      end,
      vendor: vendor_json(order.vendor),
      address: address_json(order),
      delivery_requests: order.delivery_requests.order(created_at: :desc).map do |dr|
        {
          id: dr.id,
          status: dr.status,
          vehicle_type: dr.vehicle_type,
          estimated_cost: dr.estimated_cost,
          package_details: dr.package_details,
          pickup_address: dr.pickup_address,
          delivery_address: dr.delivery_address,
          accepted_at: dr.accepted_at,
          picked_up_at: dr.picked_up_at,
          delivered_at: dr.delivered_at,
          events: dr.events,
          current_lat: dr.current_lat,
          current_lng: dr.current_lng,
          logistics_partner: dr.logistics_partner ? {
            id: dr.logistics_partner.id,
            name: dr.logistics_partner.name,
            phone: dr.logistics_partner.phone
          } : nil
        }
      end
    }

    json[:delivery_pin] = order.delivery_pin if current_user == order.user
    json[:pickup_pin] = order.pickup_pin if current_user.vendor == order.vendor
    json
  end

  def vendor_json(vendor)
    return nil unless vendor
    {
      shop_name: vendor.business_name,
      business_address: vendor.business_address,
      phone: vendor.phone,
      business_lat: vendor.business_lat,
      business_lng: vendor.business_lng
    }
  end

  def address_json(order)
    return nil unless order.shipping_address.present?

    addr = order.user.addresses.order(updated_at: :desc).first

    {
      full_address: order.shipping_address,
      phone: order.user.phone,
      latitude: addr&.latitude,
      longitude: addr&.longitude,
      delivery_notes: addr&.delivery_notes
    }
  end

  def estimated_delivery(order)
    dr = order.delivery_requests.first
    if dr&.logistics_partner&.estimated_days
      base = order.accepted_at || order.created_at
      base + dr.logistics_partner.estimated_days.days
    end
  end

  def format_currency(amount)
    parts = sprintf('%.2f', amount).split('.')
    integer_part = parts[0].reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
    "#{integer_part}.#{parts[1]}"
  end

  def base_url
    @base_url ||= request.try(:base_url) || ENV['APP_URL'] || 'http://localhost:3000'
  end

  # ── Professional bank‑style invoice (package‑safe) ──────────────────
  def invoice_html(order)
    require 'rqrcode'
    require 'base64'

    group = CheckoutGroup.find_by(id: order.checkout_group_id)
    consolidated_shipping = group&.buyer_shipping_cost.to_f

    verification_url = "#{base_url}/verify/#{order.id}?token=#{order.invoice_token}"
    qrcode = RQRCode::QRCode.new(verification_url)
    png = qrcode.as_png(size: 200).to_s
    qr_base64 = Base64.strict_encode64(png)

    items_rows = order.line_items.includes(:product, :package).map do |li|
      title = li.product&.title || li.package&.name || "Item ##{li.id}"
      "<tr>
         <td style='padding:10px 8px; border:1px solid #ddd;'>#{title}</td>
         <td style='text-align:center; padding:10px 8px; border:1px solid #ddd;'>#{li.quantity}</td>
         <td style='text-align:right; padding:10px 8px; border:1px solid #ddd;'>ETB #{format_currency(li.price)}</td>
         <td style='text-align:right; padding:10px 8px; border:1px solid #ddd;'>ETB #{format_currency(li.price * li.quantity)}</td>
       </tr>"
    end.join

    buyer_name = order.user.full_name.presence || order.user.email.presence || "User ##{order.user.id}"
    seller_name = order.vendor.business_name
    payment_status = order.payment_status.humanize.upcase
    status_color = order.payment_completed? ? '#15803D' : '#B91C1C'

    subtotal = order.line_items.sum { |li| li.price * li.quantity }.to_f
    discount = order.discount_amount.to_f
    service_fee = order.service_fee.to_f
    vat = order.vat_amount.to_f
    shipping = consolidated_shipping
    total = subtotal + service_fee + vat - discount + shipping

    logo_url = "#{base_url}/images/logo.png"

    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>Invoice ##{order.id}</title>
        <style>
          body {
            font-family: 'Segoe UI', Arial, sans-serif;
            margin: 0;
            background: #f4f4f4;
            color: #1a1a1a;
          }
          .invoice-wrapper {
            max-width: 900px;
            margin: 20px auto;
            background: #fff;
            border: 1px solid #d0d0d0;
            box-shadow: 0 4px 12px rgba(0,0,0,0.08);
            position: relative;
            overflow: hidden;
          }
          .watermark {
            position: absolute;
            top: 55%;
            left: 50%;
            transform: translate(-50%, -50%) rotate(-25deg);
            font-size: 80px;
            font-weight: 900;
            color: rgba(0, 0, 0, 0.04);
            pointer-events: none;
            white-space: nowrap;
            z-index: 0;
            letter-spacing: 4px;
            text-transform: uppercase;
          }
          .content {
            position: relative;
            z-index: 1;
            padding: 30px 40px;
          }
          .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 2px solid #333;
            padding-bottom: 16px;
            margin-bottom: 24px;
          }
          .logo {
            height: 45px;
          }
          .header-right {
            text-align: right;
          }
          .document-title {
            font-size: 24px;
            font-weight: 700;
            margin: 0;
            color: #000;
            letter-spacing: 1px;
          }
          .document-subtitle {
            font-size: 12px;
            color: #555;
            margin-top: 4px;
          }
          .info-grid {
            display: flex;
            justify-content: space-between;
            gap: 20px;
            margin-bottom: 24px;
          }
          .info-box {
            border: 1px solid #d0d0d0;
            border-radius: 4px;
            padding: 12px 16px;
            flex: 1;
          }
          .info-label {
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: #777;
            margin-bottom: 6px;
          }
          .info-value {
            font-size: 13px;
            font-weight: 600;
            color: #000;
            line-height: 1.5;
          }
          .items-table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
          }
          .items-table th {
            background: #f2f2f2;
            text-align: left;
            padding: 10px 8px;
            border: 1px solid #ddd;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 10px;
            letter-spacing: 0.5px;
            color: #444;
          }
          .items-table td {
            padding: 10px 8px;
            border: 1px solid #ddd;
            vertical-align: top;
            font-size: 12px;
          }
          .items-table tbody tr:nth-child(even) {
            background: #fcfcfc;
          }
          .totals-table {
            width: auto;
            margin-left: auto;
            font-size: 12px;
          }
          .totals-table td {
            padding: 6px 12px;
            border: none;
          }
          .totals-table tr:last-child td {
            border-top: 2px solid #333;
            font-weight: 700;
          }
          .footer {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-top: 24px;
            border-top: 1px solid #d0d0d0;
            padding-top: 16px;
            font-size: 10px;
            color: #777;
          }
          .footer .note {
            font-size: 9px;
            color: #999;
          }
          @media print {
            body {
              background: #fff;
            }
            .invoice-wrapper {
              border: none;
              box-shadow: none;
              margin: 0;
            }
            .content {
              padding: 0;
            }
          }
        </style>
      </head>
      <body>
        <div class="invoice-wrapper">
          <div class="watermark">ET Marketplace</div>
          <div class="content">
            <div class="header">
              <img src="#{logo_url}" alt="ET Marketplace" class="logo" onerror="this.style.display='none'" />
              <div class="header-right">
                <p class="document-title">TAX INVOICE</p>
                <p class="document-subtitle">Invoice #INV-#{order.id}</p>
                <p class="document-subtitle">Date: #{order.created_at.strftime('%B %d, %Y')}</p>
                <p class="document-subtitle"><span style="color:#{status_color}; font-weight:bold;">#{payment_status}</span></p>
              </div>
            </div>

            <div class="info-grid">
              <div class="info-box">
                <div class="info-label">Bill From</div>
                <div class="info-value">#{seller_name}<br>#{order.vendor.business_address}</div>
              </div>
              <div class="info-box">
                <div class="info-label">Bill To</div>
                <div class="info-value">#{buyer_name}<br>#{order.shipping_address}</div>
              </div>
            </div>

            <table class="items-table">
              <thead>
                <tr>
                  <th>Item</th>
                  <th style="text-align:center;">Qty</th>
                  <th style="text-align:right;">Unit Price</th>
                  <th style="text-align:right;">Total</th>
                </tr>
              </thead>
              <tbody>
                #{items_rows}
              </tbody>
            </table>

            <div style="display: flex; justify-content: flex-end;">
              <table class="totals-table">
                <tr><td>Subtotal</td><td style="text-align:right;">ETB #{format_currency(subtotal)}</td></tr>
                #{discount > 0 ? "<tr><td>Discount</td><td style='text-align:right;'>-ETB #{format_currency(discount)}</td></tr>" : ""}
                #{service_fee > 0 ? "<tr><td>Service Fee</td><td style='text-align:right;'>ETB #{format_currency(service_fee)}</td></tr>" : ""}
                #{vat > 0 ? "<tr><td>VAT</td><td style='text-align:right;'>ETB #{format_currency(vat)}</td></tr>" : ""}
                <tr><td>Delivery Fee</td><td style='text-align:right;'>ETB #{format_currency(shipping)}</td></tr>
                <tr><td>Total</td><td style='text-align:right;'>ETB #{format_currency(total)}</td></tr>
              </table>
            </div>

            <div style="text-align:right; margin-top:20px;">
              <img src="data:image/png;base64,#{qr_base64}" alt="Verification QR" width="100" height="100"/>
              <p style="font-size:10px; color:#555;">Verify invoice authenticity</p>
            </div>

            <div class="footer">
              <div>
                <p>Generated on #{Time.current.strftime('%B %d, %Y %I:%M %p')}</p>
                <p class="note">This is a system-generated document and does not require a physical signature.</p>
              </div>
              <div>ET Marketplace</div>
            </div>
          </div>
        </div>
      </body>
      </html>
    HTML
  end
end