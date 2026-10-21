class JsonWebToken
  SECRET_KEY = Rails.application.credentials.secret_key_base
  ALGORITHM  = 'HS256'
  ACCESS_EXPIRY  = 15.minutes
  REFRESH_EXPIRY = 24.hours

  def self.encode(payload, expiry = ACCESS_EXPIRY.from_now)
    payload[:exp] = expiry.to_i
    JWT.encode(payload, SECRET_KEY, ALGORITHM)
  end

  def self.decode(token)
    body = JWT.decode(token, SECRET_KEY, true, algorithm: ALGORITHM)[0]
    HashWithIndifferentAccess.new(body)
  rescue JWT::ExpiredSignature
    :expired
  rescue JWT::DecodeError
    nil
  end
end