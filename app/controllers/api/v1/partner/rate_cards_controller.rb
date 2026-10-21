module Api
  module V1
    module Partner
      class RateCardsController < ApplicationController
        before_action :authenticate_partner!

        # GET /api/v1/partner/rate_cards
        def index
          partner = current_user.logistics_partner
          return render json: { error: 'Not a logistics partner' }, status: :forbidden unless partner

          rate_cards = partner.rate_cards.order(:vehicle_type)
          render json: rate_cards.map { |rc|
            {
              id: rc.id,
              vehicle_type: rc.vehicle_type,
              base_rate: rc.base_rate.to_f,
              per_km_rate: rc.per_km_rate.to_f,
              min_charge: rc.min_charge.to_f,
              weight_surcharge_per_kg_above_5kg: rc.weight_surcharge_per_kg_above_5kg.to_f,
              express_surcharge_percent: rc.express_surcharge_percent.to_f,
              fragile_surcharge: rc.fragile_surcharge.to_f
            }
          }
        end

        private

        def authenticate_partner!
          unless current_user&.logistics_partner
            render json: { error: 'Unauthorized' }, status: :unauthorized
            return false
          end
          true
        end
      end
    end
  end
end