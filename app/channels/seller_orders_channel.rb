# app/channels/seller_orders_channel.rb
class SellerOrdersChannel < ApplicationCable::Channel
  def subscribed
    vendor = current_user&.vendor
    unless vendor
      reject
      return
    end

    stream_from "seller_orders_#{vendor.id}"
    Rails.logger.info "SellerOrdersChannel: User #{current_user.id} subscribed for vendor #{vendor.id}"
  end

  def unsubscribed
    Rails.logger.info "SellerOrdersChannel: User #{current_user&.id} unsubscribed"
  end

  def receive(data)
    # Reserved for future use
  end
end