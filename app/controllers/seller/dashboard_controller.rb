# app/controllers/seller/dashboard_controller.rb
class Seller::DashboardController < Seller::BaseController
  before_action :require_vendor!

  def index
    vendor = current_user.vendor
    orders = vendor.orders

    total_commissions = orders.sum(:commission_amount).to_f
    total_earnings    = orders.sum(:total).to_f - total_commissions

    # Build per‑category commission rates, respecting admin overrides
    settings_commission = Setting.get('commission') || {}
    category_overrides  = settings_commission['categoryCommission'] || {}
    default_global      = settings_commission['defaultCommission'] || 0

    vendor_category_ids = vendor.products.active.distinct.pluck(:category_id)
    category_rates = Category.where(id: vendor_category_ids).map do |cat|
      override_rate = category_overrides[cat.id.to_s]
      rate = if override_rate.present?
               override_rate.to_f
             elsif cat.commission_rate.present?
               cat.commission_rate.to_f
             else
               default_global.to_f
             end
      {
        category_id: cat.id,
        category_name: cat.name,
        commission_rate: rate
      }
    end

    # Return shipping penalties (all negative payouts = deductions)
    total_return_shipping_penalties = vendor.payouts
      .where("amount < 0")
      .sum(:amount).to_f.abs

    # Refund summary
    refunded_orders = orders.where(payment_status: :refunded)
    refunded_count  = refunded_orders.count
    total_refunded   = refunded_orders.sum(:refunded_amount).to_f

    render json: {
      # ★ Shop status – now part of the dashboard response
      is_open:           vendor.is_open,
      accepting_orders:  vendor.accepting_orders,
      reopen_at:         vendor.reopen_at,

      message: "Welcome, #{current_user.full_name}!",
      total_orders: orders.count,
      total_revenue: orders.sum(:total).to_f,
      total_earnings: total_earnings,
      total_commissions: total_commissions,
      commission_rate: vendor.effective_commission_rate,
      category_commission_rates: category_rates,
      average_order_value: orders.count > 0 ? (orders.sum(:total).to_f / orders.count.to_f).round(2) : 0.0,
      total_return_shipping_penalties: total_return_shipping_penalties,
      refunded_orders_count: refunded_count,
      total_refunded_amount: total_refunded,
      revenue_by_month: orders.group("DATE_TRUNC('month', created_at)").sum(:total)
                              .transform_keys { |k| k.strftime("%Y-%m") }
                              .transform_values(&:to_f),
      recent_orders: orders.order(created_at: :desc).limit(5).map do |o|
        {
          id: o.id,
          customer: o.user.full_name,
          total: o.total.to_f,
          status: o.status,
          payment_status: o.payment_status,
          created_at: o.created_at.strftime("%Y-%m-%d")
        }
      end
    }
  end

  # POST /seller/toggle_shop
  def toggle_shop
    vendor = current_user.vendor
    new_state = !vendor.is_open
    vendor.update!(
      is_open:          new_state,
      accepting_orders: new_state,
      reopen_at:        new_state ? nil : params[:reopen_at].presence
    )
    render json: {
      is_open:          vendor.is_open,
      accepting_orders: vendor.accepting_orders,
      reopen_at:        vendor.reopen_at,
      message:          vendor.is_open ? "Shop is now open" : "Shop is now closed"
    }
  end

  private

  def require_vendor!
    unless current_user.vendor
      render json: { error: "Seller account not set up." }, status: :forbidden
    end
  end
end