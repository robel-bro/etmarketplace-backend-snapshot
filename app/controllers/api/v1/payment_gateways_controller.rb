class Api::V1::PaymentGatewaysController < ApplicationController
  allow_unauthenticated_access only: [:index]

  def index
    gateways = PaymentGateway.active.map do |g|
      { provider: g.provider, name: g.name }
    end
    render json: gateways
  end
end