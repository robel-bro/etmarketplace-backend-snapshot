class ShippingService
  # Given two coordinates, return available shipping options from active partners
  def self.calculate_options(pickup_lat:, pickup_lng:, delivery_lat:, delivery_lng:)
    distance_km = haversine(pickup_lat, pickup_lng, delivery_lat, delivery_lng)
    partners = LogisticsPartner.active
    return [] if partners.empty?

    partners.map { |p| p.calculate_quote(distance_km) }.compact
  end

  private

  def self.haversine(lat1, lng1, lat2, lng2)
    r = 6371 # km
    dlat = (lat2 - lat1) * Math::PI / 180
    dlng = (lng2 - lng1) * Math::PI / 180
    a = Math.sin(dlat / 2)**2 + Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) * Math.sin(dlng / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    r * c
  end
end