# app/controllers/api/seller_verification_controller.rb
class Api::SellerVerificationController < ApplicationController
  before_action :require_authentication
  before_action :ensure_vendor

  def create
    # ★ Enforce location restriction – only allow sellers in configured regions
    locations_setting = Setting.get('locations', {})
    allowed = locations_setting['available_locations']

    if allowed.present?
      regions = allowed.split(',').map(&:strip).map(&:downcase)
      vendor_address = params.dig(:vendor, :business_address).to_s.downcase
      vendor_region_id = params.dig(:vendor, :region_id)

      # Try to match address or region_id against allowed regions
      in_allowed_region = regions.any? { |r| vendor_address.include?(r) }

      if vendor_region_id.present? && !in_allowed_region
        region = Region.find_by(id: vendor_region_id)
        in_allowed_region = region && regions.any? { |r| region.name.downcase.include?(r) }
      end

      unless in_allowed_region
        return render json: {
          error: "We don't currently serve your area. We only operate in: #{allowed}"
        }, status: :unprocessable_entity
      end
    end

    # Verify national ID
    verification = NationalIdVerificationService.verify(params[:vendor][:national_id])
    unless verification[:success]
      return render json: { error: verification[:message] }, status: :unprocessable_entity
    end

    if @vendor.update(vendor_params)
      render json: { message: "Seller verification submitted", vendor_id: @vendor.id }, status: :ok
    else
      render json: { errors: @vendor.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def ensure_vendor
    @vendor = current_user.vendor || current_user.build_vendor
  end

  def vendor_params
    params.require(:vendor).permit(
      :business_name,
      :tin,                    # Keep until we fully migrate (set to nil in frontend, can be removed later)
      :national_id,
      :business_address,
      :region_id,
      :is_bulk_supplier,
      :telebirr_number,
      :license_document,       # Active Storage file upload (general license)
      :id_document,             # National ID file
      :tin_certificate,        # ★ TIN certificate file (replaces tin text)
      :business_license        # Optional business license file (for bulk)
    )
  end
end