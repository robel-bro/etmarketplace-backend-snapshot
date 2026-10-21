# app/controllers/api/v1/partner/profile_controller.rb

module Api
  module V1
    module Partner
      class ProfileController < ApplicationController
        before_action :authenticate_partner!
        before_action :set_partner

        # GET /api/v1/partner/profile
        def show
          render json: partner_json(@partner)
        end

        # PATCH /api/v1/partner/toggle_online
        def toggle_online
          @partner.update!(online: !@partner.online)
          render json: { online: @partner.online }
        end

        # POST /api/v1/partner/profile_image
        def update_image
          if params[:image].present?
            @partner.logo.attach(params[:image])
          end
          render json: { logo_url: @partner.logo.attached? ? Rails.application.routes.url_helpers.rails_blob_url(@partner.logo) : nil }
        end

        # PATCH /api/v1/partner/profile
        # Allows the partner to update selected operational/contact fields and upload documents.
        def update
          # Update text fields if provided
          allowed_fields = %w[
            address
            bank_name
            account_number
            account_name
            telebirr_number
            operating_region
            phone
            name
          ]

          allowed_fields.each do |field|
            @partner[field] = params[field] if params[field].present?
          end

          # Attach documents if provided
          if params[:business_license].present?
            @partner.business_license_doc.attach(params[:business_license])
          end
          if params[:tin_doc].present?
            @partner.tin_doc.attach(params[:tin_doc])
          end
          if params[:insurance].present?
            @partner.insurance_doc.attach(params[:insurance])
          end

          if @partner.save
            render json: partner_json(@partner)
          else
            render json: { errors: @partner.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def set_partner
          @partner = current_user.logistics_partner
          return if @partner.present?

          render json: { error: 'Not a logistics partner' }, status: :forbidden
        end

        def authenticate_partner!
          partner = current_user&.logistics_partner
          unless partner && partner.active?
            render json: { error: 'Unauthorized' }, status: :unauthorized
          end
        end

        def partner_json(partner)
          {
            id: partner.id,
            name: partner.name,
            phone: partner.phone,
            email: partner.user&.email,
            address: partner.address,
            tin_number: partner.tin,
            status: partner.status,
            online: partner.online,
            commission_rate: partner.commission_rate,
            bank_name: partner.respond_to?(:bank_name) ? partner.bank_name : nil,
            account_number: partner.respond_to?(:account_number) ? partner.account_number : nil,
            account_name: partner.respond_to?(:account_name) ? partner.account_name : nil,
            telebirr_number: partner.respond_to?(:telebirr_number) ? partner.telebirr_number : nil,
            operating_region: partner.respond_to?(:operating_region) ? partner.operating_region : nil,
            logo_url: partner.logo.attached? ? Rails.application.routes.url_helpers.rails_blob_url(partner.logo) : nil,
            business_license_url: partner.business_license_doc.attached? ? Rails.application.routes.url_helpers.rails_blob_url(partner.business_license_doc) : nil,
            tin_url: partner.tin_doc.attached? ? Rails.application.routes.url_helpers.rails_blob_url(partner.tin_doc) : nil,
            insurance_url: partner.insurance_doc.attached? ? Rails.application.routes.url_helpers.rails_blob_url(partner.insurance_doc) : nil
          }
        end
      end
    end
  end
end