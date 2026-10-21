# app/controllers/api/v1/partner/drivers_controller.rb
module Api
  module V1
    module Partner
      class DriversController < ApplicationController
        before_action :authenticate_partner!
        before_action :set_partner
        before_action :set_driver, only: [:update, :destroy]

        # GET /api/v1/partner/drivers
        def index
          drivers = @partner.drivers.order(:name)
          render json: drivers.map { |d| driver_json(d) }
        end

        # POST /api/v1/partner/drivers
        def create
          driver = @partner.drivers.new(driver_params)
          if driver.save
            attach_driver_files(driver)
            render json: driver_json(driver), status: :created
          else
            render json: { errors: driver.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # PATCH /api/v1/partner/drivers/:id
        def update
          if @driver.update(driver_params)
            attach_driver_files(@driver)
            render json: driver_json(@driver)
          else
            render json: { errors: @driver.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # DELETE /api/v1/partner/drivers/:id
        def destroy
          @driver.destroy!
          head :no_content
        rescue ActiveRecord::RecordNotDestroyed => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def authenticate_partner!
          partner = current_user&.logistics_partner
          unless partner && partner.active?
            render json: { error: 'Unauthorized' }, status: :unauthorized
            return false
          end
          true
        end

        def set_partner
          @partner = current_user.logistics_partner
          unless @partner
            render json: { error: 'Not a logistics partner' }, status: :forbidden
            return false
          end
          true
        end

        def set_driver
          @driver = @partner.drivers.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: 'Driver not found' }, status: :not_found
          return false
        end

        def driver_params
          # Accept both nested (:driver) and flat params.
          if params[:driver].present?
            params.require(:driver).permit(
              :name, :phone, :license_number, :address, :status, :vehicle_id,
              :photo, :license_photo, :photoFile, :licensePhotoFile
            )
          else
            params.permit(
              :name, :phone, :license_number, :address, :status, :vehicle_id,
              :photo, :license_photo, :photoFile, :licensePhotoFile
            )
          end
        end

        def attach_driver_files(driver)
          # Prefer standard keys; fallback to frontend keys
          photo = params[:photo] || params[:photoFile]
          license_photo = params[:license_photo] || params[:licensePhotoFile]

          driver.photo.attach(photo) if photo.present?
          driver.license_photo.attach(license_photo) if license_photo.present?
        end

        def driver_json(driver)
          {
            id: driver.id,
            name: driver.name,
            phone: driver.phone,
            license_number: driver.license_number,
            address: driver.address,
            status: driver.status,
            vehicle_id: driver.vehicle_id,
            photo_url: driver.photo_url,
            license_photo_url: driver.license_photo_url
          }
        end
      end
    end
  end
end