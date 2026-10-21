module Admin
  module LogisticsPartners
    class VehiclesController < Admin::BaseController
      before_action :set_partner
      before_action :set_vehicle, only: [:update, :destroy]

      # GET /admin/logistics_partners/:partner_id/vehicles
      def index
        vehicles = @partner.vehicles.order(:created_at)
        render json: vehicles
      end

      # POST /admin/logistics_partners/:partner_id/vehicles
      def create
        vehicle = @partner.vehicles.new(vehicle_params)
        if vehicle.save
          AdminAuditLog.log(
            current_user,
            'logistics_partner_vehicle_created',
            vehicle,
            { partner_id: @partner.id, plate_number: vehicle.plate_number }
          )
          render json: vehicle, status: :created
        else
          render json: { errors: vehicle.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /admin/logistics_partners/:partner_id/vehicles/:id
      def update
        if @vehicle.update(vehicle_params)
          AdminAuditLog.log(
            current_user,
            'logistics_partner_vehicle_updated',
            @vehicle,
            { partner_id: @partner.id, plate_number: @vehicle.plate_number }
          )
          render json: @vehicle
        else
          render json: { errors: @vehicle.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /admin/logistics_partners/:partner_id/vehicles/:id
      def destroy
        @vehicle.destroy!
        AdminAuditLog.log(
          current_user,
          'logistics_partner_vehicle_deleted',
          @vehicle,
          { partner_id: @partner.id, plate_number: @vehicle.plate_number }
        )
        head :no_content
      rescue ActiveRecord::RecordNotDestroyed => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_partner
        @partner = LogisticsPartner.find(params[:logistics_partner_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Logistics partner not found" }, status: :not_found
      end

      def set_vehicle
        @vehicle = @partner.vehicles.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Vehicle not found" }, status: :not_found
      end

      def vehicle_params
        params.require(:vehicle).permit(
          :vehicle_type, :plate_number, :max_weight_kg,
          :length_cm, :width_cm, :height_cm,
          :refrigerated, :fragile_capable, :status
        ).tap do |whitelisted|
          # Normalize status: only allow available or out_of_service
          if whitelisted[:status].present?
            whitelisted[:status] = whitelisted[:status].to_s.strip.downcase
            unless %w[available busy out_of_service].include?(whitelisted[:status])
              whitelisted.delete(:status)
            end
          end

          # Normalize vehicle_type to allowed types
          if whitelisted[:vehicle_type].present?
            whitelisted[:vehicle_type] = whitelisted[:vehicle_type].to_s.strip.downcase
            unless %w[motorcycle car van truck].include?(whitelisted[:vehicle_type])
              whitelisted.delete(:vehicle_type)
            end
          end
        end
      end
    end
  end
end