# app/controllers/admin/logistics_settings_controller.rb

class Admin::LogisticsSettingsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  def show
    defaults = Setting.get('logistics_defaults') || default_values
    render json: defaults
  end

  def update
    Setting.set('logistics_defaults', params.permit!.to_h.except(:controller, :action, :format))
    render json: { message: 'Settings updated' }
  end

  private

  def default_values
    {
      rate_cards: {
        motorcycle: { base_rate: 30, per_km_rate: 10, min_charge: 50, weight_surcharge_per_kg_above_5kg: 2, express_surcharge_percent: 20, fragile_surcharge: 30 },
        car:        { base_rate: 50, per_km_rate: 15, min_charge: 100, weight_surcharge_per_kg_above_5kg: 2, express_surcharge_percent: 30, fragile_surcharge: 50 },
        van:        { base_rate: 80, per_km_rate: 20, min_charge: 150, weight_surcharge_per_kg_above_5kg: 3, express_surcharge_percent: 35, fragile_surcharge: 70 },
        truck:      { base_rate: 120, per_km_rate: 25, min_charge: 200, weight_surcharge_per_kg_above_5kg: 5, express_surcharge_percent: 40, fragile_surcharge: 100 }
      },
      vehicle_weight_thresholds: {
        motorcycle_max_kg: 20,
        car_max_kg: 200,
        van_max_kg: 1000
      },
      business_hours: {
        start: "08:00",
        end: "20:00"
      }
    }
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'logistics' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('logistics')
    head :forbidden
    false
  end
end