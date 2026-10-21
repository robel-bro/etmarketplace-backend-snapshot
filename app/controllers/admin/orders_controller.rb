class Admin::OrdersController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  def index
    page = (params[:page] || 1).to_i
    page = 1 if page < 1

    per_page = (params[:per_page] || 50).to_i
    per_page = 25 if per_page < 1 || per_page > 100

    orders = Order.includes(:user, :vendor, line_items: { product: { images_attachments: :blob } })

    # Filter by status (handles both string and integer enums)
    if params[:status].present? && params[:status] != 'all'
      status_value = params[:status]
      if defined?(Order.statuses) && Order.statuses.is_a?(Hash)
        status_value = Order.statuses[status_value] || status_value
      end
      orders = orders.where(status: status_value)
    end

    # Sorting
    sort_by = params[:sort_by] || 'created_at'
    sort_order = (params[:sort_order] || 'desc').downcase
    sort_order = 'desc' unless %w[asc desc].include?(sort_order)

    case sort_by
    when 'id', 'created_at', 'total'
      orders = orders.order("#{sort_by} #{sort_order}")
    when 'buyer'
      orders = orders.joins(:user).order("users.full_name #{sort_order}")
    when 'vendor'
      orders = orders.joins(:vendor).order("vendors.business_name #{sort_order}")
    else
      orders = orders.order("created_at #{sort_order}")
    end

    total = orders.count
    orders = orders.limit(per_page).offset((page - 1) * per_page)

    render json: {
      data: orders.map { |o| order_list_json(o) },
      meta: {
        current_page: page,
        total_count: total,
        per_page: per_page,
        total_pages: (total.to_f / per_page).ceil
      }
    }
  end

  def show
    @order = Order.includes(:user, :vendor, delivery_requests: :logistics_partner, line_items: { product: { images_attachments: :blob } })
                  .find(params[:id])
    render json: order_detail_json(@order)
  end

  def update_status
    @order = Order.find(params[:id])
    new_status = params[:status]
    if %w[pending_acceptance accepted shipped delivered cancelled returned].include?(new_status)
      @order.update!(status: new_status)
      render json: order_detail_json(@order)
    else
      render json: { error: "Invalid status" }, status: :unprocessable_entity
    end
  end

  private

  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('orders')
    head :forbidden
    false
  end

  def order_list_json(order)
    {
      id: order.id,
      buyer: order.user&.full_name || "Unknown",
      buyer_email: order.user&.email,
      vendor: order.vendor&.business_name || "Unknown",
      vendor_id: order.vendor_id,
      status: order.status,
      payment_status: order.payment_status,
      payment_method: order.payment_method_enum,
      total: order.total.to_f,
      shipping_cost: 0.0,
      items_count: order.line_items.size,
      first_item_title: order.line_items.first&.product&.title || "N/A",
      created_at: order.created_at,
      carrier: order.delivery_requests.first&.logistics_partner&.name || "N/A",
      estimated_delivery: nil
    }
  end

  def order_detail_json(order)
    group = CheckoutGroup.find_by(id: order.checkout_group_id)
    consolidated_shipping = group&.buyer_shipping_cost.to_f
    items = order.line_items.includes(product: { images_attachments: :blob })

    subtotal = items.sum { |li| li.price * li.quantity }.to_f
    discount = order.discount_amount.to_f
    service_fee = order.service_fee.to_f
    vat = order.vat_amount.to_f
    grand_total = order.total.to_f + consolidated_shipping

    estimated = nil
    dr = order.delivery_requests.first
    if dr&.logistics_partner&.estimated_days
      base = order.accepted_at || order.created_at
      estimated = base + dr.logistics_partner.estimated_days.days
    end

    # ★ Compute return deadline
    return_deadline = nil
    if order.delivered_at && order.return_window_days
      return_deadline = order.delivered_at + order.return_window_days.days
    end

    {
      id: order.id,
      status: order.status,
      payment_status: order.payment_status,
      payment_method: order.payment_method_enum,
      buyer: {
        name: order.user&.full_name,
        email: order.user&.email,
        phone: order.user&.phone
      },
      vendor: {
        id: order.vendor_id,
        name: order.vendor&.business_name,
        phone: order.vendor&.phone
      },
      items: items.map do |item|
        product = item.product
        {
          product_id: item.product_id,
          title: product&.title,
          quantity: item.quantity,
          unit_price: item.price.to_f,
          total_price: (item.price * item.quantity).to_f,
          image: product&.image_urls&.first
        }
      end,
      financial: {
        subtotal: subtotal,
        discount: discount,
        service_fee: service_fee,
        vat: vat,
        shipping_cost: consolidated_shipping,
        grand_total: grand_total
      },
      shipping_address: order.shipping_address,
      delivery: {
        carrier: dr&.logistics_partner&.name,
        tracking: dr&.tracking_number,
        estimated_delivery: estimated,
        events: dr&.events || []
      },
      dates: {
        created: order.created_at,
        accepted: order.accepted_at,
        shipped: order.shipped_at,
        delivered: order.delivered_at
      },
      invoice_url: "/invoices/#{order.id}",
      pdf_url: "/orders/#{order.id}/invoice.pdf",

      # ★ Return policy frozen on the order
      return_window_days: order.return_window_days,
      restocking_fee_percent: order.restocking_fee_percent,
      return_shipping_responsibility: order.return_shipping_responsibility,
      return_deadline: return_deadline
    }
  end
end