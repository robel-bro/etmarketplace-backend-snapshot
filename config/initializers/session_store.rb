# config/initializers/session_store.rb
if Rails.env.production?
  Rails.application.config.session_store :cookie_store,
    key:          '_et_marketplace_session',
    same_site:    :lax,
    secure:       true,
    expire_after: 7.days
else
  Rails.application.config.session_store :cookie_store,
    key:          '_et_marketplace_session',
    same_site:    :lax,
    secure:       false,
    expire_after: 7.days
end