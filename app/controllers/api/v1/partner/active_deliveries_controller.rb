# app/controllers/api/v1/partner/active_deliveries_controller.rb

module Api
  module V1
    module Partner
      class ActiveDeliveriesController < ApplicationController
        before_action :require_partner!
        before_action :set_partner
        before_action :set_delivery, only: [:update_status]

        # GET /api/v1/partner/active_deliveries
        def index
          deliveries = DeliveryRequest.where(logistics_partner: @partner)
                                     .where.not(status: ['delivered', 'completed', 'cancelled'])
                                     .includes(order: [:user, :vendor, :line_items], vehicle: [])
                                     .order(created_at: :desc)

          render json: { data: deliveries.map { |dr| active_delivery_json(dr) } }
        end

        # PATCH /api/v1/partner/active_deliveries/:id/update_status
        def update_status
          new_status = params[:status]

          case new_status
          when 'picked_up'
            return render json: { error: 'Cannot mark picked up' }, status: :unprocessable_entity unless @delivery.status.in?(['confirmed_pickup', 'accepted'])
            @delivery.mark_picked_up!
          when 'in_transit'
            return render json: { error: 'Cannot mark in transit' }, status: :unprocessable_entity unless @delivery.status == 'picked_up'
            @delivery.mark_in_transit!
          when 'delivered'
            return render json: { error: 'Cannot mark delivered' }, status: :unprocessable_entity unless @delivery.status == 'in_transit'
            @delivery.mark_delivered! # COD handling inside model
          else
            return render json: { error: 'Invalid status' }, status: :unprocessable_entity
          end

          render json: active_delivery_json(@delivery)
        rescue => e
          Rails.logger.error "Partner active delivery update failed for DR #{@delivery&.id}: #{e.message}"
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def set_partner
          @partner = current_user.logistics_partner
          unless @partner
            render json: { error: 'Not a logistics partner' }, status: :forbidden
            return false
          end
          true
        end

        def set_delivery
          @delivery = DeliveryRequest.find_by(id: params[:id], logistics_partner: @partner)
          render json: { error: 'Delivery request not found' }, status: :not_found unless @delivery
        end

        # Serialize delivery for the partner active services panel
        def active_delivery_json(dr)
          order = dr.order
          return {} unless order

          # Pickup and delivery contacts depending on return or forward
          if dr.return_request_id.present?
            pickup_contact = {
              name: order.user&.full_name,
              phone: order.user&.phone
            }
            delivery_contact = {
              name: order.vendor&.business_name,
              phone: order.vendor&.phone
            }
            is_return = true
            pickup_address = dr.pickup_address
            delivery_address = dr.delivery_address
          else
            pickup_contact = {
              name: order.vendor&.business_name,
              phone: order.vendor&.phone
            }
            delivery_contact = {
              name: order.user&.full_name,
              phone: order.user&.phone
            }
            is_return = false
            pickup_address = dr.pickup_address
            delivery_address = dr.delivery_address
          end

          products = order.line_items.map do |li|
            product = li.product
            next unless product
            {
              title: product.title || 'Unknown',
              quantity: li.quantity,
              weight_kg: product.weight_kg,
              price: product.price,
              image_url: product.images.attached? ?
                          Rails.application.routes.url_helpers.rails_blob_url(product.images.first) : nil
            }
          end.compact

          {
            id: dr.id,
            status: dr.status,
            pickup_address: pickup_address,
            delivery_address: delivery_address,
            cod_amount: order.payment_cash_on_delivery? ? order.total : nil,
            payment_method: order.payment_method_enum,
            seller: order.vendor ? {
              name: order.vendor.business_name,
              phone: order.vendor.phone
            } : nil,
            buyer: order.user ? {
              name: order.user.full_name,
              phone: order.user.phone
            } : nil,
            products: products,
            vehicle: dr.vehicle ? {
              id: dr.vehicle.id,
              plate_number: dr.vehicle.plate_number,
              vehicle_type: dr.vehicle.vehicle_type
            } : nil,
            accepted_at: dr.accepted_at,
            pickup_confirmed_at: dr.pickup_confirmed_at,
            picked_up_at: dr.picked_up_at,
            delivered_at: dr.delivered_at,
            is_return: is_return,
            return_reason: dr.return_request&.reason
          }
        end
      end
    end
  end
end