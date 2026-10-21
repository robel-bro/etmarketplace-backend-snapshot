class Seller::StatsController < Seller::BaseController
  def index
    vendor = current_user.vendor
    orders = vendor.orders

    revenue_by_month = orders
      .group("DATE_TRUNC('month', created_at)")
      .sum(:total)
      .transform_keys { |key| key.strftime("%Y-%m") }
      .transform_values(&:to_f)

    recent_orders = orders.order(created_at: :desc).limit(5).map do |order|
      {
        id: order.id,
        customer: order.user.full_name,
        total: order.total.to_f,
        status: order.status,
        created_at: order.created_at.strftime("%Y-%m-%d")
      }
    end

    total_revenue = orders.sum(:total).to_f
    total_earnings = (total_revenue - orders.sum(:commission_amount).to_f).to_f
    average_order_value = orders.count > 0 ? (total_revenue / orders.count.to_f).round(2) : 0.0

    render json: {
      total_orders: orders.count,
      total_revenue: total_revenue,
      total_earnings: total_earnings,
      average_order_value: average_order_value,
      revenue_by_month: revenue_by_month,
      recent_orders: recent_orders
    }
  end
end