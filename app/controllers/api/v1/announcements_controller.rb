module Api
  module V1
    class AnnouncementsController < ApplicationController
      allow_unauthenticated_access only: [:index]

      def index
        announcements = AdminAnnouncement.where(active: true)
                                         .where('start_date <= ?', Time.current)
                                         .where('end_date >= ? OR end_date IS NULL', Time.current)
                                         .order(created_at: :desc)
        render json: announcements.map { |a|
          {
            id: a.id,
            title: a.title,
            content: a.content,
            announcement_type: a.announcement_type,
            link: a.link,
            active: a.active,
            start_date: a.start_date,
            end_date: a.end_date
          }
        }
      end
    end
  end
end