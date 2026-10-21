# app/controllers/api/v1/notifications_controller.rb

class Api::V1::NotificationsController < ApplicationController
  before_action :require_authentication, except: [:unread_count]
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  # GET /api/v1/notifications
  def index
    notifications = current_user.notifications.recent.page(params[:page]).per(20)
    render json: {
      notifications: notifications.map { |n| notification_json(n) },
      meta: pagination_meta(notifications)
    }
  end

  # GET /api/v1/notifications/unread_count
  # ⚠️ Public endpoint returns 0 if not logged in; safe for anonymous requests.
  def unread_count
    count = current_user ? current_user.notifications.unread.count : 0
    render json: { unread_count: count }
  end

  # GET /api/v1/notifications/:id
  def show
    notification = current_user.notifications.find(params[:id])
    render json: notification_json(notification)
  end

  # PATCH /api/v1/notifications/:id/read
  def read
    notification = current_user.notifications.find(params[:id])
    notification.mark_read!
    head :no_content
  end

  # POST /api/v1/notifications/mark_all_read
  def mark_all_read
    current_user.notifications.unread.update_all(read: true)
    head :no_content
  end

  private

  def notification_json(notification)
    {
      id: notification.id,
      title: notification.title,
      body: notification.body,
      notification_type: notification.notification_type,
      read: notification.read,
      metadata: notification.metadata,
      created_at: notification.created_at
    }
  end

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      next_page: collection.next_page,
      prev_page: collection.prev_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count
    }
  end

  def not_found
    render json: { error: 'Notification not found' }, status: :not_found
  end
end