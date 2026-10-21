module Api
  module V1
    class LocationsController < ApplicationController
      skip_before_action :require_authentication

      # GET /api/v1/locations/check?region=Addis+Ababa
      def check
        locations_setting = Setting.get('locations', {})
        allowed = locations_setting['available_locations']

        if allowed.present?
          regions = allowed.split(',').map(&:strip).map(&:downcase)
          user_region = params[:region].to_s.downcase

          if user_region.present? && regions.any? { |r| user_region.include?(r) }
            render json: { allowed: true, message: "We serve your area!" }
          else
            render json: { allowed: false, message: "We don't currently serve your area. We only operate in: #{allowed}" }
          end
        else
          # No location restrictions configured – allow everyone
          render json: { allowed: true }
        end
      end
    end
  end
end