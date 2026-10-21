# app/controllers/admin/logistics_partners/drivers_controller.rb
module Admin
  module LogisticsPartners
    class DriversController < ApplicationController
      before_action :require_authentication
      before_action :authorize_admin
      before_action :set_partner
      before_action :set_driver, only: [:show, :update, :destroy]

      # GET /admin/logistics_partners/:logistics_partner_id/drivers
      def index
        drivers = @partner.drivers.order(:name)
        render json: drivers.map { |d| driver_json(d) }
      end

      # GET /admin/logistics_partners/:logistics_partner_id/drivers/:id
      def show
        render json: driver_json(@driver)
      end

      # POST /admin/logistics_partners/:logistics_partner_id/drivers
      def create
        driver = @partner.drivers.new(driver_params)
        if driver.save
          attach_driver_files(driver)
          render json: driver_json(driver), status: :created
        else
          render json: { errors: driver.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /admin/logistics_partners/:logistics_partner_id/drivers/:id
      def update
        if @driver.update(driver_params)
          attach_driver_files(@driver)
          render json: driver_json(@driver)
        else
          render json: { errors: @driver.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /admin/logistics_partners/:logistics_partner_id/drivers/:id
      def destroy
        @driver.destroy!
        head :no_content
      rescue ActiveRecord::RecordNotDestroyed => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_partner
        @partner = LogisticsPartner.find(params[:logistics_partner_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Logistics partner not found' }, status: :not_found
      end

      def set_driver
        @driver = @partner.drivers.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Driver not found' }, status: :not_found
      end

      def driver_params
        params.require(:driver).permit(
          :name, :phone, :license_number, :address, :status, :vehicle_id
        )
      end

      def attach_driver_files(driver)
        driver.photo.attach(params[:photo]) if params[:photo].present?
        driver.license_photo.attach(params[:license_photo]) if params[:license_photo].present?
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

      def authorize_admin
        return true if current_user&.admin?
        return true if current_user&.sub_admin? && current_user.permissions&.include?('logistics')
        head :forbidden
        false
      end
    end
  end
end