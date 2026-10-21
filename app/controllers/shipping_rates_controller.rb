class ShippingRatesController < ApplicationController
  # Allow unauthenticated access for calculating rates during checkout
  allow_unauthenticated_access only: [:calculate]

  # GET /shipping_rates
  # List all rates (admin only)
  def index
    @rates = ShippingRate.all
    render json: @rates
  end

  # GET /shipping_rates/calculate?address_id=xxx
  # Returns available shipping rates for the given address
  def calculate
    address = Address.find(params[:address_id])
    # Find the most specific rate for this address
    rate = ShippingRate.find_by(region: address.region, zone: address.zone, woreda: address.woreda) ||
           ShippingRate.find_by(region: address.region, zone: address.zone, woreda: nil) ||
           ShippingRate.find_by(region: address.region, zone: nil, woreda: nil)
    if rate
      render json: {
        standard: { cost: rate.standard_rate, days: rate.standard_days },
        express: { cost: rate.express_rate, days: rate.express_days }
      }
    else
      render json: { error: "No shipping rate available for this address" }, status: :not_found
    end
  end
end