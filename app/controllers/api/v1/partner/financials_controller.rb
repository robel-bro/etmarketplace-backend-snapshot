# app/controllers/api/v1/partner/financials_controller.rb
module Api
  module V1
    module Partner
      class FinancialsController < ApplicationController
        before_action :authenticate_partner!

        # GET /api/v1/partner/financials
        def show
          partner = current_user.logistics_partner

          pending_payout = PartnerPayout.where(logistics_partner: partner, status: :pending).sum(:amount).to_f
          paid_payout = PartnerPayout.where(logistics_partner: partner, status: :paid).sum(:amount).to_f

          cod_method = Order.payment_method_enums[:cash_on_delivery]

          cod_orders = partner.delivery_requests
                              .joins(:order)
                              .where(delivery_requests: { status: ['delivered', 'completed'] })
                              .where(orders: { payment_method_enum: cod_method })
                              .where("COALESCE(orders.cod_reconciled, false) = false")

          cod_owed = cod_orders.sum('orders.total').to_f
          net_balance = pending_payout - cod_owed

          transactions = []

          PartnerPayout.where(logistics_partner: partner)
                       .order(created_at: :desc)
                       .limit(20)
                       .each do |p|
            transactions << {
              type: p.status == 'paid' ? 'payout_paid' : 'payout_pending',
              description: "Delivery payout ##{p.id}",
              amount: p.amount.to_f,
              status: p.status,
              date: p.paid_at || p.created_at,
              delivery_request_id: p.delivery_request_id
            }
          end

          cod_orders.order('orders.created_at DESC').limit(20).each do |dr|
            order = dr.order
            next unless order

            items = order.line_items.includes(:product).map do |li|
              product = li.product
              {
                title: product&.title || 'N/A',
                quantity: li.quantity,
                price: li.price.to_f,
                image_url: product&.first_image_url || ''
              }
            end

            transactions << {
              type: 'cod_collected',
              description: "COD collected for order ##{order.id}",
              amount: order.total.to_f,
              status: 'pending_settlement',
              date: dr.delivered_at || dr.updated_at,
              order_id: order.id,
              items: items
            }
          end

          transactions.sort_by! { |t| t[:date] || Time.at(0) }.reverse!

          render json: {
            pending_payout: pending_payout,
            paid_payout: paid_payout,
            cod_owed: cod_owed,
            net_balance: net_balance,
            transactions: transactions
          }
        end

        private

        def authenticate_partner!
          unless current_user&.logistics_partner
            render json: { error: 'Unauthorized' }, status: :unauthorized
          end
        end
      end
    end
  end
end