class AdminDeliveriesChannel < ApplicationCable::Channel
  # Called when the consumer has successfully become subscribed.
  def subscribed
    # Only allow users with admin or sub‑admin permission to manage logistics.
    unless current_user.present? && (current_user.admin? || current_user.has_permission?('manage_logistics'))
      reject
      return
    end

    stream_from "admin_deliveries"
    Rails.logger.info "AdminDeliveriesChannel: User #{current_user.id} subscribed to admin deliveries"
  end

  # Called when the consumer has unsubscribed.
  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
    Rails.logger.info "AdminDeliveriesChannel: User #{current_user&.id} unsubscribed"
  end
end