# app/controllers/admin/settings_controller.rb

class Admin::SettingsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  ALLOWED_SETTING_KEYS = %w[
    commission
    membership
    orders_block
    seller_health
    locations
    tax_and_fees
    shipping_markup_percent
    order_block_start
    order_block_end
    daily_order_block_start
    daily_order_block_end
  ].freeze

  def index
    settings = Setting.all.each_with_object({}) do |s, hash|
      hash[s.key] = begin
        JSON.parse(s.value)
      rescue
        s.value
      end
    end

    # Build nested `orders_block` for frontend compatibility
    if %w[order_block_start order_block_end daily_order_block_start daily_order_block_end].any? { |k| settings.key?(k) }
      settings['orders_block'] = {
        'order_block_start' => settings['order_block_start'],
        'order_block_end' => settings['order_block_end'],
        'daily_block_start' => settings['daily_order_block_start'],
        'daily_block_end' => settings['daily_order_block_end'],
      }
    end

    render json: settings
  end

  def update
    changes = {}
    params[:settings].each do |key, value|
      # Only allow known setting keys
      next unless ALLOWED_SETTING_KEYS.include?(key.to_s)

      old = Setting.get(key)
      Setting.set(key, value)
      changes[key] = { old: old, new: value }

      # ★ Special handling: `orders_block` should also save individual top‑level keys
      # used by CheckoutService and other services.
      if key.to_s == 'orders_block' && value.is_a?(Hash)
        {
          'order_block_start' => value['order_block_start'],
          'order_block_end' => value['order_block_end'],
          'daily_order_block_start' => value['daily_block_start'],
          'daily_order_block_end' => value['daily_block_end'],
        }.each do |flat_key, flat_value|
          if ALLOWED_SETTING_KEYS.include?(flat_key)
            old_flat = Setting.get(flat_key)
            Setting.set(flat_key, flat_value)
            changes[flat_key] = { old: old_flat, new: flat_value }
          end
        end
      end
    end

    AdminAuditLog.log(current_user, 'settings_updated', nil, changes) if changes.any?
    render json: { success: true }
  end

  private

  # ★ UPDATED: Allow main admin or sub-admin with 'settings' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('settings')
    head :forbidden
    false
  end
end