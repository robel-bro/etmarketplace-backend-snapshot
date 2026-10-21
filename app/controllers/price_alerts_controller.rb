# app/controllers/price_alerts_controller.rb
class PriceAlertsController < ApplicationController
  before_action :require_authentication

  # GET /price_alerts
  def index
    alerts = current_user.price_alerts
    render json: alerts
  end

  # POST /price_alerts
  def create
    alert = current_user.price_alerts.new(price_alert_params)
    if alert.save
      render json: alert, status: :created
    else
      render json: { errors: alert.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /price_alerts/:id
  def destroy
    alert = current_user.price_alerts.find(params[:id])
    alert.destroy
    head :no_content
  end

  private

  def price_alert_params
    params.require(:price_alert).permit(:product_id, :target_price)
  end
end