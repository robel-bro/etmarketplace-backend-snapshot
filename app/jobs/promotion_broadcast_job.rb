class PromotionBroadcastJob < ApplicationJob
  queue_as :default

  # Sends a promotion/announcement to all users (respecting preferences)
  # type: a valid notification_type, e.g. :flash_deal_started, :new_collection, :promotion, :announcement
  # metadata: hash with title, body, deep_link etc. (passed straight to NotificationService)
  def perform(type, metadata = {})
    # Filter users who have push notifications enabled (everyone gets in‑app)
    # For promotional emails, only those who opted in will be emailed inside NotificationService
    User.where(push_notifications: true).find_each do |user|
      NotificationService.notify(user, type.to_sym, metadata.symbolize_keys)
    end
  end
end