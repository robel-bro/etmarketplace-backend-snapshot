require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module EtMarketplaceBackend
  class Application < Rails::Application
    config.load_defaults 8.1

    # Autoload lib directory for classes like JsonWebToken
    config.autoload_paths << Rails.root.join('app/lib')

    config.autoload_lib(ignore: %w[assets tasks])

    # Enable Rack::Attack for rate limiting / brute‑force protection
    config.middleware.use Rack::Attack

    config.api_only = false

    # JWT secret – production uses environment variable, development falls back to a safe default
    config.x.jwt_secret = if Rails.env.production?
                            ENV.fetch('JWT_SECRET')   # Raises error if missing
                          else
                            ENV.fetch('JWT_SECRET', 'dev_fallback_secret_change_me')
                          end
  end
end