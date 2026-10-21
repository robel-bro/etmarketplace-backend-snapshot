class Rack::Attack
  # ─── Global throttle ──────────────────────────
  # only throttle API requests; static assets are not affected
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip if req.path.start_with?('/api', '/login', '/sign_up', '/checkout', '/cart', '/wishlist')
  end

  # ─── Checkout (order placement) – very strict ──
  throttle('checkout/ip', limit: 5, period: 60.seconds) do |req|
    req.ip if req.path == '/checkout' && req.post?
  end

  # ─── Login attempts ────────────────────────────
  throttle('logins/ip', limit: 5, period: 60.seconds) do |req|
    req.ip if req.path == '/login' && req.post?
  end

  # ─── OTP verifications ─────────────────────────
  throttle('otp/ip', limit: 3, period: 60.seconds) do |req|
    req.ip if req.path == '/verify_otp' && req.post?
  end

  # ─── Signups ────────────────────────────────────
  throttle('signups/ip', limit: 3, period: 60.seconds) do |req|
    req.ip if req.path == '/sign_up' && req.post?
  end

  # ─── Block obviously malicious user‑agents ──────
  blocklist('bad_bots') do |req|
    req.user_agent =~ /(scanner|bot|spider)/i
  end
end