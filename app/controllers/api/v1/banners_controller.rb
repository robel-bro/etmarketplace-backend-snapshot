module Api
  module V1
    class BannersController < ApplicationController
      allow_unauthenticated_access only: [:index]   # ✅ added

      def index
        banners = AdminAnnouncement.where(announcement_type: 'banner', active: true)
                                   .order(created_at: :desc)
                                   .limit(5)
        render json: banners.map { |b| banner_json(b) }
      end

      private

      def banner_json(banner)
        # Use the same host/port logic as Product and Vendor models
        host = ActiveStorage::Current.url_options&.dig(:host) || 'localhost'
        port = ActiveStorage::Current.url_options&.dig(:port) || 3000

        img = if banner.image.attached?
                Rails.application.routes.url_helpers.rails_blob_url(
                  banner.image,
                  host: host,
                  port: port,
                  only_path: false
                )
              else
                nil
              end

        {
          id: banner.id,
          title: banner.title,
          description: banner.content,
          image_url: img,
          image: img,
          link: banner.link.presence,
          start_date: banner.start_date,
          end_date: banner.end_date
        }
      end
    end
  end
end