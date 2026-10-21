class Webhooks::TelebirrController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_authentication

  def create
    gateway_config = PaymentGateway.active.find_by(provider: 'telebirr')
    return head :not_found unless gateway_config

    body = request.body.read
    payload = JSON.parse(body) rescue {}

    # Extract numeric order ID (e.g., "ORDER60GCQI5OPW" → 60)
    raw_order_id = payload['merch_order_id'] || ''
    numeric_id = raw_order_id.scan(/\d+/).first
    order = numeric_id ? Order.find_by(id: numeric_id) : nil

    if Gateway::Telebirr.verify_notification(payload.dup, gateway_config)
      if order
        order.update!(status: :paid, payment_status: :completed)
      end
      head :ok
    else
      head :forbidden
    end
  end
end