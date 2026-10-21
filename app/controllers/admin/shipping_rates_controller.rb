class Admin::ShippingRatesController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_shipping_rate, only: [:show, :update, :destroy]

  def index
    @shipping_rates = ShippingRate.all
    render json: @shipping_rates.as_json(include: [:region, :zone, :woreda])
  end

  def show
    render json: @shipping_rate.as_json(include: [:region, :zone, :woreda])
  end

  def create
    @shipping_rate = ShippingRate.new(shipping_rate_params)
    if @shipping_rate.save
      render json: @shipping_rate, status: :created
    else
      render json: { errors: @shipping_rate.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @shipping_rate.update(shipping_rate_params)
      render json: @shipping_rate
    else
      render json: { errors: @shipping_rate.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @shipping_rate.destroy
    head :no_content
  end

  private

  def set_shipping_rate
    @shipping_rate = ShippingRate.find(params[:id])
  end

  def shipping_rate_params
    params.require(:shipping_rate).permit(:region_id, :zone_id, :woreda_id, :standard_rate, :express_rate, :standard_days, :express_days)
  end

  def authorize_admin
    head :forbidden unless current_user.admin?
  end
end