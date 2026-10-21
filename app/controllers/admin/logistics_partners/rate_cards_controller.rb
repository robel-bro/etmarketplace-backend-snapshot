module Admin
  module LogisticsPartners
    class RateCardsController < Admin::BaseController
      before_action :set_partner
      before_action :set_rate_card, only: [:update, :destroy]

      # GET /admin/logistics_partners/:partner_id/rate_cards
      def index
        rate_cards = @partner.rate_cards.order(:vehicle_type)
        render json: rate_cards
      end

      # POST /admin/logistics_partners/:partner_id/rate_cards
      def create
        rate_card = @partner.rate_cards.new(rate_card_params)
        if rate_card.save
          AdminAuditLog.log(
            current_user,
            'logistics_partner_rate_card_created',
            rate_card,
            { partner_id: @partner.id, vehicle_type: rate_card.vehicle_type }
          )
          render json: rate_card, status: :created
        else
          render json: { errors: rate_card.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /admin/logistics_partners/:partner_id/rate_cards/:id
      def update
        if @rate_card.update(rate_card_params)
          AdminAuditLog.log(
            current_user,
            'logistics_partner_rate_card_updated',
            @rate_card,
            { partner_id: @partner.id, vehicle_type: @rate_card.vehicle_type }
          )
          render json: @rate_card
        else
          render json: { errors: @rate_card.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /admin/logistics_partners/:partner_id/rate_cards/:id
      def destroy
        @rate_card.destroy!
        AdminAuditLog.log(
          current_user,
          'logistics_partner_rate_card_deleted',
          @rate_card,
          { partner_id: @partner.id, vehicle_type: @rate_card.vehicle_type }
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

      def set_rate_card
        @rate_card = @partner.rate_cards.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Rate card not found" }, status: :not_found
      end

      def rate_card_params
        params.require(:rate_card).permit(
          :vehicle_type, :base_rate, :per_km_rate, :min_charge,
          :weight_surcharge_per_kg_above_5kg,
          :express_surcharge_percent, :fragile_surcharge
        ).tap do |whitelisted|
          # Normalize vehicle_type to allowed types
          if whitelisted[:vehicle_type].present?
            whitelisted[:vehicle_type] = whitelisted[:vehicle_type].to_s.strip.downcase
            unless %w[motorcycle car van truck].include?(whitelisted[:vehicle_type])
              whitelisted.delete(:vehicle_type)
            end
          end

          # Clamp numeric fields to non-negative values
          %i[
            base_rate per_km_rate min_charge
            weight_surcharge_per_kg_above_5kg
            express_surcharge_percent fragile_surcharge
          ].each do |field|
            if whitelisted[field].present?
              value = whitelisted[field].to_f
              value = 0.0 if value < 0
              # Express surcharge percent should be between 0 and 100
              if field == :express_surcharge_percent
                value = 0.0 if value < 0
                value = 100.0 if value > 100
              end
              whitelisted[field] = value
            end
          end
        end
      end
    end
  end
end