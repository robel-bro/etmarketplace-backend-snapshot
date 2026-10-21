class DeliveryChannel < ApplicationCable::Channel
  # Called when a buyer subscribes to track a specific order
  def subscribed
    order = Order.find_by(id: params[:order_id])
    if order && (order.user_id == current_user.id || current_user.admin?)
      stream_for order
    else
      reject
    end
  end

  def unsubscribed
    # Any cleanup needed
  end
end