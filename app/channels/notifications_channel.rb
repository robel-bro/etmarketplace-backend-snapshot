class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    # Each user gets a stream named "notifications:#{user.id}"
    stream_for current_user
  end

  def unsubscribed
    # Any cleanup
  end
end