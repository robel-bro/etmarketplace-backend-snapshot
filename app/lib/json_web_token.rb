# app/lib/json_web_token.rb
class JsonWebToken
  SECRET_KEY = ENV.fetch('JWT_SECRET') {
    Rails.env.production? ? (raise 'JWT_SECRET environment variable not set') : 'dev_secret_key_change_in_production'
  }

  ALGORITHM      = 'HS256'
  ACCESS_EXPIRY  = 2.hours
  REFRESH_EXPIRY = 7.days

  # Encode access token with user roles and vendor_id
  def self.encode_access(user)
    payload = {
      user_id:   user.id,
      roles:     user.roles,                          # array – e.g. ["buyer"] or ["seller","admin"]
      vendor_id: user.respond_to?(:vendor) ? user.vendor&.id : nil,
      exp:       ACCESS_EXPIRY.from_now.to_i,
      iat:       Time.current.to_i,
      type:      'access'
    }
    JWT.encode(payload, SECRET_KEY, ALGORITHM)
  end

  # Encode refresh token with unique jti (for future multi-device support)
  def self.encode_refresh(user)
    payload = {
      user_id: user.id,
      jti:     SecureRandom.uuid,
      exp:     REFRESH_EXPIRY.from_now.to_i,
      iat:     Time.current.to_i,
      type:    'refresh'
    }
    JWT.encode(payload, SECRET_KEY, ALGORITHM)
  end

  # Generic decode – returns :expired, nil, or HashWithIndifferentAccess
  def self.decode(token)
    body = JWT.decode(token, SECRET_KEY, true, algorithm: ALGORITHM)[0]
    HashWithIndifferentAccess.new(body)
  rescue JWT::ExpiredSignature
    :expired
  rescue JWT::DecodeError
    nil
  end

  # Decode and validate that it's an access token
  def self.decode_access(token)
    decoded = decode(token)
    return nil if decoded == :expired || decoded.nil? || !decoded.is_a?(Hash)
    decoded[:type] == 'access' ? decoded : nil
  end

  # Decode and validate that it's a refresh token
  def self.decode_refresh(token)
    decoded = decode(token)
    return nil if decoded == :expired || decoded.nil? || !decoded.is_a?(Hash)
    decoded[:type] == 'refresh' ? decoded : nil
  end
end