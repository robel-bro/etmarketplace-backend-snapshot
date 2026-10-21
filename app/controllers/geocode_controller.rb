# app/controllers/geocode_controller.rb
class GeocodeController < ApplicationController
  skip_before_action :require_authentication, raise: false
  skip_before_action :verify_authenticity_token

  # GET /geocode/reverse?lat=9.03&lon=38.76
  def reverse
    lat = params[:lat].to_f
    lon = params[:lon].to_f

    if lat.zero? || lon.zero? || lat.abs > 90 || lon.abs > 180
      render json: { error: 'Invalid coordinates' }, status: :unprocessable_entity
      return
    end

    result = GeocodingService.reverse_geocode_with_structure(lat, lon)
    Rails.logger.info "GEOCODE_DEBUG reverse result: #{result.inspect}"
    render json: {
      address: result[:formatted_address],
      structured: result[:structured]
    }
  end

  # GET /geocode/search?query=...
  def search
    query = params[:query].to_s.strip
    if query.blank?
      render json: { results: [] }, status: :ok
      return
    end

    result = GeocodingService.geocode(query)
    render json: { results: [result].compact }
  end

  # POST /geocode/validate_place
  def validate_place
    address = params[:address].to_s.strip
    if address.blank?
      render json: { error: 'Address is required' }, status: :unprocessable_entity
      return
    end

    result = GeocodingService.ultimate_geocode(address)

    if result[:lat] == 9.0243 && result[:lng] == 38.7468 && result[:structured][:confidence] < 3
      render json: {
        error: 'Could not determine location from the provided address. Please add more details (subcity, woreda, street).',
        structured: result[:structured]
      }, status: :unprocessable_entity
      return
    end

    render json: {
      lat: result[:lat],
      lng: result[:lng],
      formatted_address: result[:formatted_address],
      structured: result[:structured]
    }
  rescue => e
    Rails.logger.error "Validate place error: #{e.message}"
    render json: { error: 'Geocoding failed' }, status: :unprocessable_entity
  end

  # GET /geocode/suggest?query=...
  def suggest
    query = params[:query].to_s.strip
    suggestions = GeocodingService.suggest(query)
    render json: { suggestions: suggestions }
  end
end