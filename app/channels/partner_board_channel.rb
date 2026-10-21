# app/channels/partner_board_channel.rb
class PartnerBoardChannel < ApplicationCable::Channel
  def subscribed
    partner = current_user&.logistics_partner
    unless partner&.active?
      reject
      return
    end

    # Use stream_for so that PartnerBoardChannel.broadcast_to(partner, ...) works correctly
    stream_for partner
    Rails.logger.info "PartnerBoardChannel: User #{current_user.id} subscribed for partner #{partner.id}"
  end

  def unsubscribed
    Rails.logger.info "PartnerBoardChannel: User #{current_user&.id} unsubscribed"
  end

  def receive(data)
    # Reserved
  end
end