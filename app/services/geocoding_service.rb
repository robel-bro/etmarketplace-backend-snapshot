# app/services/geocoding_service.rb
class GeocodingService
  CACHE_TTL = 24.hours
  V2_BASE = "https://mapapi.gebeta.app/v2/search"
  V1_BASE = "https://mapapi.gebeta.app/api/v1/route"

  ADDIS_SUBCITIES = [
    "Addis Ketema", "Akaky Kaliti", "Arada", "Bole", "Gullele",
    "Kirkos", "Kolfe Keranio", "Lideta", "Nifas Silk-Lafto", "Yeka"
  ].freeze

  WOREDA_PATTERN = /(?:woreda|wereda)\s*(\d+)/i
  SUB_CITY_PATTERN = /(#{ADDIS_SUBCITIES.join('|')})/i

  # ─── Public API ────────────────────────────────────
  def self.geocode(address_string)
    forward_geocode(address_string)
  end

  def self.reverse_geocode(lat, lng)
    reverse_geocode_v2(lat, lng)
  end

  def self.reverse_geocode_with_structure(lat, lng)
    structured = reverse_structured(lat, lng)
    parts = [
      structured[:street],
      structured[:landmark],
      structured[:neighborhood],
      structured[:woreda],
      structured[:sub_city],
      structured[:city],
      "Ethiopia"
    ].compact
    {
      formatted_address: parts.join(", ").presence || "#{lat.round(4)}, #{lng.round(4)}",
      structured: structured
    }
  end

  def self.ultimate_geocode(raw_text)
    return default_result if raw_text.blank?

    text = raw_text.strip.downcase
    forward = forward_geocode(text)
    return default_result if forward[:lat].nil? || forward[:lat] == 9.0243 && forward[:lng] == 38.7468

    structured = reverse_structured(forward[:lat], forward[:lng])
    parsed = parse_address_text(text)
    final = merge_structured(structured, parsed)
    build_result(forward, final)
  end

  # ─── Suggestions (now uses V1 for local accuracy) ──
  def self.suggest(query)
    return [] if query.blank?
    Rails.cache.fetch("gebeta_suggest:#{query}", expires_in: 5.minutes) do
      uri = URI("#{V1_BASE}/geocoding")
      uri.query = URI.encode_www_form(name: query, apiKey: api_key, country: 'et')
      res = Net::HTTP.get_response(uri)
      if res.code.to_i == 200
        data = JSON.parse(res.body)
        results = data['data'] || []
        results.map do |r|
          {
            label: [r['name'], r['city'], r['country']].compact.join(', '),
            lat: r['lat'].to_f,
            lng: r['lng'].to_f
          }
        end
      else
        []
      end
    end
  rescue => e
    Rails.logger.error "Gebeta suggest error: #{e.message}"
    []
  end

  private

  def self.api_key
    ENV['GEBETA_API_KEY'] || raise("GEBETA_API_KEY missing")
  end

  # ─── Forward geocode (V1 first, V2 fallback) ────────
  def self.forward_geocode(address)
    # Try V1 local search first (more accurate for Ethiopian addresses)
    v1 = v1_forward_search(address)
    return v1 if v1

    # Fallback to V2 general search
    v2_forward_geocode(address)
  end

  def self.v1_forward_search(query)
    Rails.cache.fetch("gebeta_v1_fwd:#{query}", expires_in: CACHE_TTL) do
      uri = URI("#{V1_BASE}/geocoding")
      params = { name: query, apiKey: api_key, country: 'et' }
      uri.query = URI.encode_www_form(params)
      res = Net::HTTP.get_response(uri)
      if res.code.to_i == 200
        data = JSON.parse(res.body)
        results = data['data'] || []
        first = results.find { |r| r['lat'].present? && r['lng'].present? }
        if first
          {
            lat: first['lat'].to_f,
            lng: first['lng'].to_f,
            formatted_address: [first['name'], first['city'], first['country']].compact.join(', '),
            city: first['city']
          }
        else
          nil
        end
      else
        nil
      end
    end
  rescue => e
    Rails.logger.error "Gebeta V1 forward error: #{e.message}"
    nil
  end

  def self.v2_forward_geocode(address)
    Rails.cache.fetch("gebeta_v2_fwd:#{address}", expires_in: CACHE_TTL) do
      uri = URI("#{V2_BASE}/geocode")
      uri.query = URI.encode_www_form(query: address, apiKey: api_key, limit: 1)
      res = Net::HTTP.get_response(uri)
      if res.code.to_i == 200
        data = JSON.parse(res.body)
        result = data.dig('data', 'results')&.first
        if result
          {
            lat: result.dig('location', 'lat').to_f,
            lng: result.dig('location', 'lng').to_f,
            formatted_address: result['display_name'],
            city: result.dig('address', 'city')
          }
        else
          { lat: 9.0243, lng: 38.7468, formatted_address: address, city: nil }
        end
      else
        { lat: 9.0243, lng: 38.7468, formatted_address: address, city: nil }
      end
    end
  rescue => e
    Rails.logger.error "Gebeta V2 forward error: #{e.message}"
    { lat: 9.0243, lng: 38.7468, formatted_address: address, city: nil }
  end

  # ─── Reverse methods (unchanged) ────────────────────
  def self.reverse_geocode_v1(lat, lng)
    Rails.cache.fetch("gebeta_v1_rev:#{lat.round(4)}:#{lng.round(4)}", expires_in: CACHE_TTL) do
      uri = URI("#{V1_BASE}/revgeocoding")
      uri.query = URI.encode_www_form(lat: lat, lon: lng, apiKey: api_key)
      res = Net::HTTP.get_response(uri)
      if res.code.to_i == 200
        JSON.parse(res.body)
      else
        {}
      end
    end
  rescue => e
    Rails.logger.error "Gebeta V1 reverse error: #{e.message}"
    {}
  end

  def self.reverse_geocode_v2(lat, lng)
    Rails.cache.fetch("gebeta_v2_rev:#{lat.round(4)}:#{lng.round(4)}", expires_in: CACHE_TTL) do
      uri = URI("#{V2_BASE}/reverse-geocoding")
      uri.query = URI.encode_www_form(lat: lat, lon: lng, apiKey: api_key, size: 5)
      res = Net::HTTP.get_response(uri)
      if res.code.to_i == 200
        data = JSON.parse(res.body)
        data.dig('data', 'results') || []
      else
        []
      end
    end
  rescue => e
    Rails.logger.error "Gebeta V2 reverse error: #{e.message}"
    []
  end

  # ────────────────────────────────────────────────────
  # Distance helper (Haversine formula in meters)
  # ────────────────────────────────────────────────────
  def self.haversine_distance(lat1, lon1, lat2, lon2)
    rad_per_deg = Math::PI / 180
    earth_radius_m = 6_371_000

    dlat_rad = (lat2 - lat1) * rad_per_deg
    dlon_rad = (lon2 - lon1) * rad_per_deg

    a = Math.sin(dlat_rad / 2) ** 2 +
        Math.cos(lat1 * rad_per_deg) * Math.cos(lat2 * rad_per_deg) *
        Math.sin(dlon_rad / 2) ** 2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    earth_radius_m * c
  end

  def self.reverse_structured(lat, lng)
    v1_payload = reverse_geocode_v1(lat, lng)
    v1_payload = v1_payload.is_a?(Hash) ? v1_payload : {}
    v2_results = reverse_geocode_v2(lat, lng)

    city    = nil
    subcity = nil
    woreda  = nil
    street  = nil
    landmark = nil
    neighborhood = nil

    # --- Extract from V1 `address` object ---
    addr = v1_payload['address']
    if addr
      city = addr.dig('municipality', 'EN') || addr.dig('county', 'EN') || addr.dig('province', 'EN')
      subcity = addr.dig('borough', 'EN')
      woreda = addr.dig('district', 'EN')
    end

    # Fallback city
    if city.blank?
      (v1_payload['data'] || []).each do |place|
        if place['City'].present?
          city = place['City']
          break
        end
      end
    end

    # --- Neighborhood from V1 area-type places (closest) ---
    area_types = /condominium|square|complex|sefer|mender|village|site/i
    candidates = v1_payload['data'] || []

    candidates_with_distance = candidates.map do |place|
      dist = haversine_distance(lat, lng, place['latitude'], place['longitude'])
      { place: place, distance: dist }
    end.sort_by { |c| c[:distance] }

    neighborhood_candidate = candidates_with_distance.find do |c|
      name = c[:place]['name'].to_s
      type = c[:place]['type'].to_s
      next false if name.match?(/pharmacy|restaurant|bar|hotel|cafe|shop/i)
      name.match?(area_types) || type.match?(area_types)
    end
    neighborhood = neighborhood_candidate[:place]['name'] if neighborhood_candidate
    neighborhood = neighborhood&.sub(/\s*\(.*?\)\s*/, '')&.strip

    # --- Landmark: use V2 first (public landmarks), then V1 business ---
    v2_landmark_cats = %w[attraction hospital school place_of_worship building]
    v2_landmark = v2_results.find do |feat|
      v2_landmark_cats.include?(feat['category']&.downcase) && feat['name'].present?
    end
    if v2_landmark
      landmark = v2_landmark['name']
    else
      # V1 fallback: pick closest business/POI that is not the neighborhood
      poi_types = /restaurant|bar|cafe|shop|store|pharmacy|drug|transport|coorporate|office/i
      landmark_candidate = candidates_with_distance.find do |c|
        name = c[:place]['name'].to_s
        type = c[:place]['type'].to_s
        next false unless type.match?(poi_types)
        next false if name == neighborhood || name.sub(/\s*\(.*?\)\s*/, '').strip == neighborhood
        true
      end
      landmark = landmark_candidate[:place]['name'] if landmark_candidate
    end

    # If still empty, use any non-establishment V1 entry
    if landmark.blank?
      fallback = candidates_with_distance.find do |c|
        name = c[:place]['name'].to_s
        type = c[:place]['type'].to_s
        next false if name == neighborhood
        type != 'establishment'
      end
      landmark = fallback[:place]['name'] if fallback
    end

    # --- Street from V2 ---
    street_cats = %w[highway residential secondary tertiary primary road]
    v2_results.each do |feature|
      cat = feature['category']&.downcase
      name = feature['name']
      if street_cats.include?(cat) && street.blank?
        street = name
      end
      if city.blank?
        city = feature.dig('address', 'city')
      end
    end

    {
      city:         city || 'Addis Ababa',
      sub_city:     subcity,
      woreda:       woreda,
      street:       street,
      landmark:     landmark,
      neighborhood: neighborhood,
      confidence:   calculate_confidence(subcity, woreda, street, landmark)
    }
  end

  def self.calculate_confidence(sub_city, woreda, street, landmark)
    score = 0
    score += 3 if sub_city.present?
    score += 3 if woreda.present?
    score += 2 if street.present?
    score += 2 if landmark.present?
    score > 10 ? 10 : score
  end

  def self.parse_address_text(text)
    result = {}
    if (match = text.match(SUB_CITY_PATTERN))
      result[:sub_city] = match[1]
    end
    if (match = text.match(WOREDA_PATTERN))
      result[:woreda] = "Woreda #{match[1]}"
    end
    result[:city] = "Addis Ababa" if text.include?("addis") || result[:sub_city].present?
    result
  end

  def self.merge_structured(api_data, parsed_data)
    {
      city:         api_data[:city]         || parsed_data[:city],
      sub_city:     api_data[:sub_city]     || parsed_data[:sub_city],
      woreda:       api_data[:woreda]       || parsed_data[:woreda],
      street:       api_data[:street],
      landmark:     api_data[:landmark],
      neighborhood: api_data[:neighborhood],
      confidence:   api_data[:confidence]   || 0
    }
  end

  def self.build_result(forward, final)
    formatted = [
      final[:street],
      final[:landmark],
      final[:neighborhood],
      final[:woreda],
      final[:sub_city],
      final[:city],
      "Ethiopia"
    ].compact.join(", ")

    {
      lat: forward[:lat],
      lng: forward[:lng],
      formatted_address: formatted.presence || forward[:formatted_address],
      structured: final
    }
  end

  def self.default_result
    {
      lat: nil,
      lng: nil,
      formatted_address: "",
      structured: { city: "Addis Ababa", confidence: 0 }
    }
  end
end