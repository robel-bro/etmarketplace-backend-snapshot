# app/controllers/shipping_estimate_controller.rb
class ShippingEstimateController < ApplicationController
  # GET /shipping_estimate?vendor_id=3&address_id=5
  # or GET /shipping_estimate?vendor_id=3&lat=9.03&lng=38.74
  def show
    vendor = Vendor.approved.find_by(id: params[:vendor_id])
    return render json: { error: 'Vendor not found' }, status: :not_found unless vendor

    # Determine buyer coordinates
    lat = params[:lat].present? ? params[:lat].to_f : nil
    lng = params[:lng].present? ? params[:lng].to_f : nil

    if lat.nil? || lng.nil?
      # No coordinates – try address
      address = current_user.addresses.find_by(id: params[:address_id]) if params[:address_id].present?
      if address
        if address.latitude && address.longitude
          lat = address.latitude.to_f
          lng = address.longitude.to_f
        else
          # Geocode the address string if possible
          if address.full_address.present?
            coords = GeocodingService.geocode(address.full_address)
            if coords && coords[:lat] && coords[:lng]
              lat = coords[:lat].to_f
              lng = coords[:lng].to_f
              # Save the coordinates for next time
              address.update_columns(latitude: lat, longitude: lng)
            end
          end
          return render json: { error: 'Address not found or missing coordinates' }, status: :not_found unless lat && lng
        end
      else
        return render json: { error: 'Provide coordinates or address_id' }, status: :unprocessable_entity
      end
    end

    # Ensure vendor has coordinates (geocode if missing)
    unless vendor.business_lat && vendor.business_lng
      if vendor.business_address.present?
        coords = GeocodingService.geocode(vendor.business_address)
        vendor.update_columns(business_lat: coords[:lat], business_lng: coords[:lng]) if coords
      end
      return render json: { error: 'Seller location unavailable' }, status: :unprocessable_entity unless vendor.business_lat
    end

    # Calculate distance
    distance_km = haversine(vendor.business_lat, vendor.business_lng, lat, lng)

    # Get options from active logistics partners
    options = LogisticsPartner.active.map do |partner|
      quote = partner.calculate_quote(distance_km)
      next unless quote
      {
        partner_name: partner.name,
        delivery_speed: partner.delivery_speed,
        estimated_days: partner.estimated_days,
        charge: quote[:charge]
      }
    end.compact.sort_by { |o| o[:estimated_days] }

    render json: { options: options }
  end

  private

  def haversine(lat1, lng1, lat2, lng2)
    r = 6371.0
    dlat = (lat2 - lat1) * Math::PI / 180
    dlng = (lng2 - lng1) * Math::PI / 180
    a = Math.sin(dlat / 2)**2 + Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) * Math.sin(dlng / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    (r * c).round(2)
  end
end