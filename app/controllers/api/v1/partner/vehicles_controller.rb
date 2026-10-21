# app/controllers/api/v1/partner/vehicles_controller.rb
module Api
  module V1
    module Partner
      class VehiclesController < ApplicationController
        before_action :authenticate_partner!
        before_action :set_partner
        before_action :set_vehicle, only: [:update, :destroy]

        # GET /api/v1/partner/vehicles
        def index
          vehicles = @partner.vehicles.order(:created_at)
          render json: vehicles.map { |v| vehicle_json(v) }
        end

        # POST /api/v1/partner/vehicles
        def create
          vehicle = @partner.vehicles.new(vehicle_params)
          if vehicle.save
            render json: vehicle_json(vehicle), status: :created
          else
            render json: { errors: vehicle.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # PATCH /api/v1/partner/vehicles/:id
        def update
          if @vehicle.update(vehicle_params)
            render json: vehicle_json(@vehicle)
          else
            render json: { errors: @vehicle.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # DELETE /api/v1/partner/vehicles/:id
        def destroy
          # Prevent deletion of a vehicle currently assigned to an active delivery
          active_deliveries = ::DeliveryRequest.where(vehicle: @vehicle)
                                               .where.not(status: ['completed', 'cancelled'])
                                               .exists?
          if active_deliveries
            return render json: { error: 'Vehicle is assigned to an active delivery and cannot be deleted.' }, status: :unprocessable_entity
          end

          @vehicle.destroy!
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

        def set_vehicle
          @vehicle = @partner.vehicles.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: 'Vehicle not found' }, status: :not_found
          return false
        end

        def vehicle_params
          params.require(:vehicle).permit(
            :vehicle_type, :plate_number, :max_weight_kg,
            :max_volume_cm3,
            :length_cm, :width_cm, :height_cm,
            :refrigerated, :fragile_capable,
            :driver_name, :driver_phone,
            :status
          ).tap do |whitelisted|
            # Normalize vehicle_type
            if whitelisted[:vehicle_type].present?
              whitelisted[:vehicle_type] = whitelisted[:vehicle_type].to_s.strip.downcase
              unless %w[motorcycle car van truck].include?(whitelisted[:vehicle_type])
                whitelisted.delete(:vehicle_type)
              end
            end

            # Normalize status: accept both 'maintenance' and 'out_of_service'
            if whitelisted[:status].present?
              status = whitelisted[:status].to_s.strip.downcase
              # Map frontend legacy status to model's 'maintenance'
              status = 'maintenance' if status == 'out_of_service'
              unless %w[available busy maintenance].include?(status)
                whitelisted.delete(:status)
              else
                whitelisted[:status] = status
              end
            end

            # Convert boolean fields from string if needed
            whitelisted[:refrigerated] = whitelisted[:refrigerated].to_s.downcase == 'true' if whitelisted.key?(:refrigerated)
            whitelisted[:fragile_capable] = whitelisted[:fragile_capable].to_s.downcase == 'true' if whitelisted.key?(:fragile_capable)
          end
        end

        def vehicle_json(v)
          {
            id: v.id,
            vehicle_type: v.vehicle_type,
            plate_number: v.plate_number,
            max_weight_kg: v.max_weight_kg.to_f,
            max_volume_cm3: v.max_volume_cm3&.to_f,
            length_cm: v.length_cm,
            width_cm: v.width_cm,
            height_cm: v.height_cm,
            refrigerated: v.refrigerated,
            fragile_capable: v.fragile_capable,
            driver_name: v.driver_name,
            driver_phone: v.driver_phone,
            status: v.status
          }
        end
      end
    end
  end
end