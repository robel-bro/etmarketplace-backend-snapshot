# app/controllers/admin/dashboard_controller.rb

class Admin::DashboardController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  def index
    total_revenue   = Order.sum(:total) || 0
    total_orders    = Order.count
    total_sellers   = Vendor.approved.count
    total_buyers    = User.where(status: :active, role_mask: 1).count
    orders_by_status = Order.group(:status).count.transform_keys { |k| Order.statuses.key(k) }
    revenue_today   = Order.where('created_at >= ?', Time.current.beginning_of_day).sum(:total) || 0
    recent_orders   = Order.includes(:user)
                           .order(created_at: :desc)
                           .limit(5)
                           .map { |o| order_summary(o) }
    pending_approvals = Vendor.pending.count

    # Revenue by month – safe SQL without groupdate
    monthly_data = Order.where('created_at >= ?', 12.months.ago)
                        .group(Arel.sql("DATE_TRUNC('month', created_at)"))
                        .order(Arel.sql("DATE_TRUNC('month', created_at)"))
                        .sum(:total)
    revenue_by_month = monthly_data.map do |date, sum|
      { month: date.strftime('%B %Y'), revenue: sum.to_f }
    end

    # Top sellers – safe aggregation
    top_sellers = Vendor.approved
                        .joins(:orders)
                        .where(orders: { status: :completed })
                        .group('vendors.id')
                        .select('vendors.id, vendors.business_name, SUM(orders.total) AS total_revenue')
                        .order('total_revenue DESC')
                        .limit(5)
                        .map do |v|
      { id: v.id, business_name: v.business_name, revenue: v.total_revenue.to_f }
    end

    render json: {
      total_revenue: total_revenue,
      total_orders: total_orders,
      total_sellers: total_sellers,
      total_buyers: total_buyers,
      orders_by_status: orders_by_status,
      revenue_today: revenue_today,
      recent_orders: recent_orders,
      pending_approvals: pending_approvals,
      top_sellers: top_sellers,
      revenue_by_month: revenue_by_month
    }
  rescue => e
    Rails.logger.error "Dashboard error: #{e.message}"
    render json: { error: "Failed to load dashboard data" }, status: :internal_server_error
  end

  def stats
    # Safe, groupdate-free stats
    render json: {
      revenue_by_month: Order.where('created_at >= ?', 12.months.ago)
                             .group(Arel.sql("DATE_TRUNC('month', created_at)"))
                             .sum(:total)
                             .map { |date, sum| { month: date.strftime('%B %Y'), revenue: sum.to_f } },
      total_orders: Order.count,
      total_revenue: Order.sum(:total) || 0,
      orders_by_status: Order.group(:status).count.transform_keys { |k| Order.statuses.key(k) },
      recent_orders: Order.includes(:user).order(created_at: :desc).limit(5).map { |o| order_summary(o) }
    }
  rescue => e
    Rails.logger.error "Stats error: #{e.message}"
    render json: { error: "Failed to load stats" }, status: :internal_server_error
  end

  private

  def order_summary(order)
    {
      id: order.id,
      total: order.total,
      status: order.status,
      customer_name: order.user&.full_name || "Unknown",
      created_at: order.created_at
    }
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'dashboard' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('dashboard')
    head :forbidden
    false
  end
end