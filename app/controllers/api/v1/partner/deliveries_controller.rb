# app/controllers/api/v1/partner/deliveries_controller.rb
module Api
  module V1
    module Partner
      class DeliveriesController < ApplicationController
        before_action :authenticate_partner!

        # GET /api/v1/partner/active_deliveries
        def active
          partner = current_user.logistics_partner

          base_scope = partner.delivery_requests
                              .where(status: ['assigned', 'accepted', 'confirmed_pickup', 'picked_up', 'in_transit', 'delivered'])
                              .order(updated_at: :desc)
                              .includes(:driver, :vehicle, order: [:user, :vendor, line_items: { product: { images_attachments: :blob } }])

          page = (params[:page] || 1).to_i
          per_page = [(params[:per_page] || 20).to_i, 100].min
          total_count = base_scope.count
          deliveries = base_scope.limit(per_page).offset((page - 1) * per_page)

          render json: {
            data: deliveries.map { |dr| delivery_json(dr) },
            meta: {
              current_page: page,
              per_page: per_page,
              total_count: total_count,
              next_page: (page * per_page) < total_count ? page + 1 : nil,
              prev_page: page > 1 ? page - 1 : nil
            }
          }
        end

        # PATCH /api/v1/partner/active_deliveries/:id/update_status
        def update_status
          partner = current_user.logistics_partner

          delivery = partner.delivery_requests.find(params[:id])
          new_status = params[:status].to_s

          case new_status
          when 'confirm_pickup'
            unless delivery.status == 'accepted'
              return render json: { error: "Cannot confirm pickup from #{delivery.status}" }, status: :unprocessable_entity
            end
            delivery.confirm_pickup_by_seller!(location: params[:location])
          when 'picked_up'
            unless %w[accepted confirmed_pickup].include?(delivery.status)
              return render json: { error: "Cannot pick up from #{delivery.status}" }, status: :unprocessable_entity
            end
            delivery.mark_picked_up!(location: params[:location])
          when 'in_transit'
            unless delivery.status == 'picked_up'
              return render json: { error: "Cannot start transit from #{delivery.status}" }, status: :unprocessable_entity
            end
            delivery.mark_in_transit!(location: params[:location])
          when 'delivered'
            unless delivery.status == 'in_transit'
              return render json: { error: "Cannot deliver from #{delivery.status}" }, status: :unprocessable_entity
            end
            cod_amount = params[:cod_amount].to_f if delivery.order.payment_cash_on_delivery?
            delivery.mark_delivered!(location: params[:location], cod_collected: cod_amount)
          else
            return render json: { error: 'Invalid status transition' }, status: :unprocessable_entity
          end

          render json: { message: 'Status updated', status: delivery.status }
        rescue ActiveRecord::RecordNotFound
          render json: { error: 'Delivery not found' }, status: :not_found
        rescue => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def delivery_json(dr)
          order = dr.order
          return nil unless order

          seller = order.vendor
          buyer = order.user
          driver = dr.driver
          vehicle = dr.vehicle

          # Preload product images to avoid N+1
          products = order.line_items.includes(product: { images_attachments: :blob }).map do |li|
            product = li.product
            next unless product

            image_url = product.image_urls.first rescue nil
            {
              title: product.title,
              quantity: li.quantity,
              weight_kg: product.weight_kg,
              price: product.price,
              image_url: image_url
            }
          end.compact

          {
            id: dr.id,
            status: dr.status,
            pickup_address: dr.pickup_address,
            delivery_address: dr.delivery_address,
            cod_amount: order.payment_cash_on_delivery? ? order.total : nil,
            payment_method: order.payment_method,
            seller: seller ? { name: seller.business_name, phone: seller.user&.phone } : nil,
            buyer: buyer ? { name: buyer.full_name, phone: buyer.phone } : nil,
            driver: driver ? { id: driver.id, name: driver.name, phone: driver.phone, photo_url: driver.photo_url } : nil,
            vehicle: vehicle ? { id: vehicle.id, plate_number: vehicle.plate_number, vehicle_type: vehicle.vehicle_type } : nil,
            products: products,
            accepted_at: dr.accepted_at,
            pickup_confirmed_at: dr.respond_to?(:pickup_confirmed_at) ? dr.pickup_confirmed_at : nil,
            picked_up_at: dr.picked_up_at,
            delivered_at: dr.delivered_at
          }
        end

        def authenticate_partner!
          partner = current_user&.logistics_partner
          unless partner && partner.active?
            render json: { error: 'Unauthorized' }, status: :unauthorized
            return false
          end
          true
        end
      end
    end
  end
end