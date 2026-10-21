class BulkOrdersController < ApplicationController
  before_action :require_authentication
  before_action :ensure_company
  before_action :validate_global_block!, only: [:create]   # long‑term block
  before_action :validate_daily_block!, only: [:create]    # ← NEW daily block
  before_action :validate_vendors_open!, only: [:create]   # vendor check

  def index
    @orders = current_user.bulk_orders
    render json: @orders.as_json(include: { bulk_order_items: { include: :product } })
  end

  def create
    @order = current_user.bulk_orders.new(bulk_order_params)
    if @order.save
      render json: @order, status: :created
    else
      render json: { errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def bulk_order_params
    params.require(:bulk_order).permit(bulk_order_items_attributes: [:product_id, :quantity])
  end

  def ensure_company
    head :forbidden unless current_user.is_company?
  end

  # ── Long‑term admin block ──
  def validate_global_block!
    block_start = Setting.get('order_block_start')
    block_end   = Setting.get('order_block_end')
    if block_start.present? && block_end.present?
      start_time = (Time.parse(block_start) rescue nil)
      end_time   = (Time.parse(block_end) rescue nil)
      if start_time && end_time && Time.current.between?(start_time, end_time)
        render json: { errors: ["Orders are temporarily paused. We'll be back by #{end_time.strftime('%B %d at %I:%M %p')}."] }, status: :unprocessable_entity
      end
    end
  end

  # ── NEW: Daily recurring block ──
  def validate_daily_block!
    daily_start = Setting.get('daily_order_block_start')
    daily_end   = Setting.get('daily_order_block_end')
    if daily_start.present? && daily_end.present?
      current_time = Time.current.strftime("%H:%M")
      if daily_start < daily_end
        # Normal day interval (e.g., 09:00 to 17:00)
        if current_time >= daily_start && current_time <= daily_end
          render json: { errors: ["Orders are paused during daily maintenance hours (#{daily_start} - #{daily_end})."] }, status: :unprocessable_entity
        end
      else
        # Crosses midnight (e.g., 23:00 to 06:00)
        if current_time >= daily_start || current_time <= daily_end
          render json: { errors: ["Orders are paused during daily maintenance hours (#{daily_start} - #{daily_end})."] }, status: :unprocessable_entity
        end
      end
    end
  end

  # ── Per‑vendor acceptance check ──
  def validate_vendors_open!
    items_params = params.dig(:bulk_order, :bulk_order_items_attributes) || []
    product_ids = items_params.map { |item| item[:product_id] }.compact.uniq

    return if product_ids.empty?

    vendors = Product.where(id: product_ids).includes(:vendor).map(&:vendor).uniq

    closed_vendors = vendors.reject { |v| v.accepting_orders? }

    if closed_vendors.any?
      messages = closed_vendors.map do |vendor|
        msg = "#{vendor.business_name} is currently closed"
        msg += " (reopens at #{vendor.reopen_at.strftime('%B %d, %Y at %I:%M %p')})" if vendor.reopen_at.present?
        msg
      end
      render json: { errors: messages }, status: :unprocessable_entity
    end
  end
end