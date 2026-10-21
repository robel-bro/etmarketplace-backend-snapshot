class AnnouncementsController < ApplicationController
  allow_unauthenticated_access only: [:index]

  def index
    announcements = Announcement.active.order(created_at: :desc)
    render json: announcements
  end
end