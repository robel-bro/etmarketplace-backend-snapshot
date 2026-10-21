# app/controllers/api/v1/profiles_controller.rb

module Api
  module V1
    class ProfilesController < ApplicationController
      include Authentication
      before_action :require_authentication, except: [:verify_location]
      before_action :ensure_active_user, only: [:update]

      # POST /api/v1/verify-location
      def verify_location
        allowed = Setting.get('available_locations') || 'Addis Ababa, Dire Dawa, Mekelle, Bahir Dar, Hawassa'
        allowed_regions = allowed.split(',').map(&:strip).reject(&:blank?)
        region = params[:region].to_s.strip
        full_location = params[:location].to_s.strip

        # 1. Region must be in the allowed list
        unless allowed_regions.include?(region)
          render json: { allowed: false, message: "We do not currently operate in #{region}." }
          return
        end

        # 2. Geocode the actual address (clean format)
        if full_location.present?
          begin
            require 'net/http'
            require 'uri'
            require 'json'

            # Extract sub-city and woreda from the formatted string
            sub_city = full_location[/Sub‑city:\s*(.+?),/, 1] || full_location[/Zone:\s*(.+?),/, 1]
            woreda   = full_location[/Woreda:\s*(.+)$/, 1]

            clean_address = [sub_city, woreda, region, 'Ethiopia'].compact.join(', ')
            Rails.logger.info "📍 Geocoding address: #{clean_address}"

            url = URI("https://nominatim.openstreetmap.org/search?q=#{URI.encode_www_form_component(clean_address)}&format=json&limit=1&addressdetails=1&countrycodes=et")
            http = Net::HTTP.new(url.host, url.port)
            http.use_ssl = true
            request = Net::HTTP::Get.new(url)
            request['User-Agent'] = 'ETMarketplace/1.0 (admin@etmarketplace.com)'

            response = http.request(request)
            data = JSON.parse(response.body) rescue []

            Rails.logger.info "📍 Nominatim response: #{data.first&.dig('display_name') || 'empty'}"

            if data.empty?
              render json: { allowed: false, message: "We could not find this address. Please check your region, sub‑city, and woreda and try again." }
              return
            end

            display_name = data.first['display_name'].to_s.downcase
            unless display_name.include?(region.downcase)
              render json: { allowed: false, message: "The address you entered does not appear to be in #{region}. Please enter a valid address." }
              return
            end

          rescue => e
            Rails.logger.error "Nominatim geocoding error: #{e.message}"
            # If geocoding fails, we still allow the submission but log the error.
          end
        end

        render json: { allowed: true }
      end

      # PATCH /api/v1/profile/fcm_token
      # Registers/updates the user's Firebase Cloud Messaging token.
      # ★ Also clears the token from any other user to prevent cross-account notifications.
      def update_fcm_token
        token = params[:fcm_token].to_s.strip
        return render json: { error: 'FCM token required' }, status: :unprocessable_entity if token.blank?

        # Clear this token from any other user
        User.where(fcm_token: token).where.not(id: current_user.id).update_all(fcm_token: nil)

        current_user.update!(fcm_token: token)
        head :no_content
      rescue => e
        Rails.logger.error "[FCM Token] Update failed: #{e.message}"
        render json: { error: 'Unable to update token' }, status: :unprocessable_entity
      end

      # DELETE /api/v1/profile/fcm_token
      # Clears the user's FCM token (e.g., on logout).
      def clear_fcm_token
        current_user.update!(fcm_token: nil)
        head :no_content
      rescue => e
        Rails.logger.error "[FCM Token] Clear failed: #{e.message}"
        render json: { error: 'Unable to clear token' }, status: :unprocessable_entity
      end

      # PATCH/PUT /api/v1/profile
      def update
        user = current_user

        permitted = if params[:user].present?
                      params.require(:user).permit(
                        :full_name, :phone, :fcm_token,
                        :national_id, :shop_name, :shop_location, :tin,
                        :business_license, :is_bulk_supplier, :telebirr_number
                      )
                    else
                      params.permit(
                        :full_name, :phone, :fcm_token,
                        :national_id, :shop_name, :shop_location, :tin,
                        :business_license, :is_bulk_supplier, :telebirr_number
                      )
                    end

        if permitted[:business_license].present?
          user.business_license.attach(permitted.delete(:business_license))
        end

        if permitted.key?(:is_bulk_supplier)
          is_bulk = ActiveModel::Type::Boolean.new.cast(permitted.delete(:is_bulk_supplier))
          vendor = user.vendor || user.build_vendor

          if vendor.new_record?
            vendor.business_name = permitted[:shop_name].presence || user.shop_name.presence || "My Shop"
            vendor.status = :pending unless vendor.status.present?
            vendor.business_address = permitted[:shop_location].presence || user.shop_location.presence || "Ethiopia"
          end

          vendor.is_bulk_supplier = is_bulk
          vendor.telebirr_number = permitted[:telebirr_number] if permitted[:telebirr_number].present?

          unless vendor.save
            render json: { errors: vendor.errors.full_messages }, status: :unprocessable_entity
            return
          end
        end

        if permitted[:shop_name].present? && user.vendor.nil?
          vendor = user.build_vendor(
            business_name: permitted[:shop_name],
            status: :pending,
            business_address: permitted[:shop_location].presence || "Ethiopia",
            telebirr_number: permitted[:telebirr_number]
          )
          vendor.save
        end

        permitted.delete(:telebirr_number)

        if user.update(permitted)
          render json: {
            user: {
              id: user.id,
              phone: user.phone,
              full_name: user.full_name,
              phone_verified: user.phone_verified,
              roles: user.roles,
              fcm_token: user.fcm_token,
              national_id: user.national_id,
              shop_name: user.shop_name,
              shop_location: user.shop_location,
              tin: user.tin,
              business_license_url: user.business_license.attached? ? url_for(user.business_license) : nil
            }
          }
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end
end