# app/controllers/api/v1/delivery_verifications_controller.rb

module Api
  module V1
    class DeliveryVerificationsController < ApplicationController
      before_action :require_authentication, except: [:verify_pin]
      before_action :set_delivery_request, except: [:verify_pin]

      # POST /api/v1/delivery_verifications/verify_pin
      # Public endpoint – no login required.
      # Driver enters Order ID + PIN.
      #   step = 'pickup'   → verifies seller's pickup_pin and marks picked_up
      #   step = 'delivery' → verifies buyer's delivery_pin and marks delivered
      def verify_pin
        order_id = params[:order_id].to_i
        pin      = params[:pin].to_s.strip
        step     = params[:step].to_s.downcase

        return render json: { error: 'Order ID required' }, status: :unprocessable_entity if order_id <= 0
        return render json: { error: 'PIN required' }, status: :unprocessable_entity if pin.blank?
        return render json: { error: 'Step required' }, status: :unprocessable_entity if step.blank?

        @dr = DeliveryRequest.find_by(order_id: order_id)
        return render json: { error: 'Delivery request not found' }, status: :not_found unless @dr

        if step == 'pickup'
          # Driver at seller: verify pickup_pin
          unless @dr.status == 'accepted'
            return render json: { error: "Cannot pick up from #{@dr.status}" }, status: :unprocessable_entity
          end

          if @dr.order.pickup_pin.blank? || @dr.order.pickup_pin != pin
            return render json: { error: 'Invalid pickup PIN' }, status: :unprocessable_entity
          end

          @dr.mark_picked_up!(location: params[:location])
          @dr.add_event(status: 'driver_picked_up_with_pin', note: 'Driver verified pickup PIN')
          render json: { message: 'Pickup confirmed', status: @dr.status }

        elsif step == 'delivery'
          # Driver at buyer: verify delivery_pin
          unless @dr.status == 'in_transit'
            return render json: { error: "Cannot deliver from #{@dr.status}" }, status: :unprocessable_entity
          end

          if @dr.order.delivery_pin.blank? || @dr.order.delivery_pin != pin
            return render json: { error: 'Invalid delivery PIN' }, status: :unprocessable_entity
          end

          cod_amount = params[:cod_amount].to_f if @dr.order.payment_method_cash_on_delivery?
          @dr.mark_delivered!(location: params[:location], cod_collected: cod_amount)
          @dr.add_event(status: 'driver_delivered_with_pin', note: 'Driver verified delivery PIN')
          render json: { message: 'Delivery confirmed', status: @dr.status }

        else
          render json: { error: 'Invalid step' }, status: :unprocessable_entity
        end
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/delivery_verifications/:delivery_request_id/seller_confirm
      def seller_confirm
        unless @dr.status == 'accepted'
          return render json: { error: "Request must be in 'accepted' status" }, status: :unprocessable_entity
        end

        unless current_user.id == @dr.order.vendor.user_id
          return render json: { error: 'Only the seller can confirm pickup' }, status: :forbidden
        end

        @dr.confirm_pickup_by_seller!(location: params[:location])
        render json: { message: 'Pickup confirmed', status: @dr.status }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/delivery_verifications/:delivery_request_id/driver_picked_up
      def driver_picked_up
        partner = current_user.logistics_partner
        unless partner && @dr.logistics_partner_id == partner.id
          return render json: { error: 'Not your delivery' }, status: :forbidden
        end

        unless %w[accepted confirmed_pickup].include?(@dr.status)
          return render json: { error: "Cannot pick up from #{@dr.status}" }, status: :unprocessable_entity
        end

        @dr.mark_picked_up!(location: params[:location])
        render json: { message: 'Picked up', status: @dr.status }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/delivery_verifications/:delivery_request_id/driver_delivered
      def driver_delivered
        partner = current_user.logistics_partner
        unless partner && @dr.logistics_partner_id == partner.id
          return render json: { error: 'Not your delivery' }, status: :forbidden
        end

        unless @dr.status == 'in_transit'
          return render json: { error: "Cannot deliver from #{@dr.status}" }, status: :unprocessable_entity
        end

        cod_amount = params[:cod_amount].to_f if @dr.order.payment_method_cash_on_delivery?
        @dr.mark_delivered!(location: params[:location], cod_collected: cod_amount)
        render json: { message: 'Delivered', status: @dr.status }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/delivery_verifications/:delivery_request_id/buyer_confirm
      def buyer_confirm
        unless current_user.id == @dr.order.user_id
          return render json: { error: 'Only the buyer can confirm delivery' }, status: :forbidden
        end

        unless @dr.status == 'delivered'
          return render json: { error: 'Delivery must be marked as delivered first' }, status: :unprocessable_entity
        end

        pin = params[:pin].to_s.strip
        if @dr.order.delivery_pin.blank? || @dr.order.delivery_pin != pin
          return render json: { error: 'Invalid delivery PIN' }, status: :unprocessable_entity
        end

        @dr.add_event(status: 'buyer_confirmed', note: "Buyer confirmed delivery with PIN")

        if @dr.order.payment_method_cash_on_delivery?
          @dr.update!(cod_status: 3)  # verified
          @dr.add_event(status: 'cod_verified', note: "COD auto‑verified by buyer PIN confirmation")
        end

        @dr.complete!

        render json: { message: 'Delivery confirmed', status: @dr.status }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/delivery_verifications/:delivery_request_id/admin_verify_cod
      def admin_verify_cod
        unless current_user.admin?
          return render json: { error: 'Only admin can verify COD' }, status: :forbidden
        end

        unless @dr.cod_status == 2  # collected
          return render json: { error: 'COD not collected yet' }, status: :unprocessable_entity
        end

        @dr.verify_cod!
        render json: { message: 'COD verified', status: @dr.status }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_delivery_request
        @dr = DeliveryRequest.find(params[:delivery_request_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Delivery request not found' }, status: :not_found
        return false
      end
    end
  end
end