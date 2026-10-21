# app/controllers/api/v1/partner_board_controller.rb
module Api
  module V1
    class PartnerBoardController < ApplicationController
      before_action :authenticate_partner!
      before_action :set_partner

      # GET /api/v1/partner_board
      def index
        @partner_vehicles = @partner.vehicles.available.to_a

        requests = ::DeliveryRequest.where(status: 'pending_assignment')
                                    .includes(order: { line_items: [:product, :package] })
                                    .order(created_at: :desc)

        if params[:search].present?
          term = "%#{params[:search].downcase}%"
          requests = requests.joins(order: { line_items: [:product, :package] })
                             .where(
                               "CAST(delivery_requests.id AS TEXT) ILIKE :term OR " \
                               "delivery_requests.pickup_address ILIKE :term OR " \
                               "delivery_requests.delivery_address ILIKE :term OR " \
                               "orders.id::text ILIKE :term OR " \
                               "products.title ILIKE :term OR " \
                               "packages.name ILIKE :term",
                               term: term
                             )
                             .distinct
        end

        requests = requests.where(required_vehicle_type: params[:vehicle_type]) if params[:vehicle_type].present?

        if params[:fulfillable_only].to_s == 'true'
          eligible_ids = requests.select { |dr| vehicle_capable?(dr) }.map(&:id)
          requests = requests.where(id: eligible_ids)
        end

        all_requests = requests.to_a
        eligible = []
        non_eligible = []

        all_requests.each do |dr|
          if vehicle_capable?(dr)
            eligible << dr
          else
            non_eligible << dr
          end
        end

        sorted_requests = eligible + non_eligible

        render json: sorted_requests.map { |dr| board_payload_with_flag(dr) }.compact
      end

      # POST /api/v1/partner_board/:id/accept
      def accept
        dr = ::DeliveryRequest.find(params[:id])
        vehicle = @partner.vehicles.find(params[:vehicle_id])
        driver = @partner.drivers.find(params[:driver_id]) if params[:driver_id].present?

        unless vehicle.available?
          return render json: { error: 'Vehicle not available' }, status: :unprocessable_entity
        end

        unless vehicle.logistics_partner_id == @partner.id
          return render json: { error: 'Vehicle does not belong to partner' }, status: :unprocessable_entity
        end

        if driver
          unless driver.available?
            return render json: { error: 'Driver is not available' }, status: :unprocessable_entity
          end
          unless driver.logistics_partner_id == @partner.id
            return render json: { error: 'Driver does not belong to partner' }, status: :unprocessable_entity
          end
        end

        begin
          ActiveRecord::Base.transaction do
            dr.assign_to_partner!(@partner, vehicle)
            dr.accept_assignment!(@partner, vehicle, driver)
          end

          # ★ Send notifications after assignment
          if dr.status == 'accepted'
            send_driver_assignment_notifications(dr)
          end

          Rails.logger.info "Partner #{@partner.id} accepted request #{dr.id} with vehicle #{vehicle.plate_number} and driver #{driver&.name}"
          render json: { message: 'Request accepted', status: dr.status }
        rescue => e
          Rails.logger.error "Accept failed for DR #{dr.id}: #{e.class} - #{e.message}"
          render json: { error: 'Unable to accept this request. Please try again.' }, status: :unprocessable_entity
        end
      end

      private

      def authenticate_partner!
        partner = current_user&.logistics_partner
        unless partner && partner.active?
          render json: { error: 'Unauthorized' }, status: :unauthorized
        end
      end

      def set_partner
        @partner = current_user.logistics_partner
        unless @partner
          render json: { error: 'Not a logistics partner' }, status: :forbidden
          return false
        end
        true
      end

      def board_payload_with_flag(dr)
        payload = ::AssignmentService.board_payload(@partner, dr)
        return nil unless payload

        payload[:can_accept] = vehicle_capable?(dr)
        payload
      end

      def vehicle_capable?(dr)
        required_type = dr.required_vehicle_type
        weight_kg = dr.package_details&.dig('chargeable_weight_kg') ||
                    dr.package_details&.dig('weight_kg').to_f
        volume_cm3 = dr.package_details&.dig('volume_cm3').to_f
        refrigerated = dr.package_details&.dig('refrigerated') || false
        fragile = dr.package_details&.dig('fragile') || false

        @partner_vehicles.any? do |vehicle|
          next false if required_type.present? && vehicle.vehicle_type != required_type
          next false if vehicle.max_weight_kg && vehicle.max_weight_kg < weight_kg
          next false if volume_cm3 > 0 && vehicle.max_volume_cm3 && vehicle.max_volume_cm3 < volume_cm3
          next false if refrigerated && !vehicle.refrigerated
          next false if fragile && !vehicle.fragile_capable
          true
        end
      end

      # ★ Notify seller and buyer about assigned driver & vehicle
      def send_driver_assignment_notifications(delivery_request)
        order = delivery_request.order
        driver = delivery_request.driver
        vehicle = delivery_request.vehicle
        company_name = delivery_request.logistics_partner&.name || 'Logistics Partner'

        payload = {
          type: 'driver_assigned',
          order_id: order.id,
          driver_name: driver&.name,
          driver_phone: driver&.phone,
          driver_photo_url: driver&.photo_url,
          vehicle_plate: vehicle&.plate_number,
          vehicle_type: vehicle&.vehicle_type,
          logistics_company_name: company_name,
          status: delivery_request.status
        }

        # Seller
        if order.vendor&.user
          NotificationService.notify(order.vendor.user, :driver_assigned_to_seller, payload)
        end

        # Buyer
        NotificationService.notify(order.user, :driver_assigned_to_buyer, payload)

        # Real-time updates
        ActionCable.server.broadcast("order_#{order.id}", {
          type: 'driver_assigned',
          payload: payload
        })
      end
    end
  end
end