# app/services/gebeta_maps_service.rb

require 'net/http'
require 'uri'
require 'json'

class GebetaMapsService
  BASE_URL = 'https://mapapi.gebeta.app/api/route/direction/'.freeze
  API_KEY = ENV['GEBETA_MAPS_API_KEY'].presence

  # Returns { distance_km: Float, duration_minutes: Integer } or nil
  def self.route(origin:, destination:, waypoints: [])
    return nil if API_KEY.blank?

    waypoint_str = waypoints.map { |w| "#{w[0]},#{w[1]}" }.join(';')
    params = {
      origin: "#{origin[0]},#{origin[1]}",
      destination: "#{destination[0]},#{destination[1]}",
      apiKey: API_KEY
    }
    params[:waypoints] = waypoint_str if waypoint_str.present?

    uri = URI(BASE_URL)
    uri.query = URI.encode_www_form(params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    return nil unless response.code.to_i == 200

    data = JSON.parse(response.body) rescue nil
    return nil unless data

    extract_route_data(data)
  rescue StandardError => e
    Rails.logger.warn "GebetaMapsService route failed: #{e.message}"
    nil
  end

  def self.haversine_distance(lat1, lng1, lat2, lng2)
    r = 6371.0
    dlat = (lat2 - lat1) * Math::PI / 180
    dlng = (lng2 - lng1) * Math::PI / 180
    a = Math.sin(dlat / 2)**2 + Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) * Math.sin(dlng / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    (r * c).round(2)
  end

  private

  def self.extract_route_data(data)
    routes = data['routes'] || data['data'] || data
    route = routes.is_a?(Array) ? routes.first : routes

    distance_m = route['distance'] || route['distance_meters'] || route['distance_m']
    duration_s = route['duration'] || route['duration_seconds'] || route['duration_s']

    # If nested in legs
    if distance_m.nil? && route['legs'].is_a?(Array)
      distance_m = route['legs'].sum { |leg| leg['distance'] || leg['distance_m'] || 0 }
      duration_s = route['legs'].sum { |leg| leg['duration'] || leg['duration_s'] || 0 }
    end

    return nil if distance_m.nil? || duration_s.nil?

    {
      distance_km: (distance_m.to_f / 1000.0).round(2),
      duration_minutes: (duration_s.to_f / 60.0).round
    }
  rescue => e
    Rails.logger.warn "GebetaMapsService parse failed: #{e.message}"
    nil
  end
end