# config/routes.rb
Rails.application.routes.draw do
  # Health check
  get "up", to: "rails/health#show", as: :rails_health_check

  # Public legal pages
  get 'legal/:key', to: 'legal_pages#show'

  # ActionCable
  mount ActionCable.server => '/cable'

  # Public regions
  resources :regions, only: [:index, :show]

  # Checkout & orders
  resources :addresses, only: [:index, :show, :create, :update, :destroy]

  post 'checkout',                    to: 'checkout#create'
  post 'checkout/summary',            to: 'checkout#summary'   # ★ NEW: pre‑order summary
  post 'validate_coupon',             to: 'checkout#validate_coupon'
  get  'checkout/payment_options',    to: 'checkout#payment_options'
  post 'checkout/shipping_options',   to: 'checkout#shipping_options'

  resources :orders, only: [:index, :show, :update] do
    member do
      get :invoice
      get :invoice_data
      get :invoice_pdf_data
    end
    resources :delivery_requests, only: [:index, :create]
  end
  # Keep legacy accept/status endpoints for admin/internal use
  post   '/delivery_requests/:id/accept',  to: 'delivery_requests#accept'
  patch  '/delivery_requests/:id/status',  to: 'delivery_requests#update_status'

  # Auth
  post '/login', to: 'sessions#create'
  post '/refresh', to: 'sessions#refresh'
  delete '/logout', to: 'sessions#destroy'
  delete '/account', to: 'users#destroy'

  post '/send_otp', to: 'registrations#send_otp'
  post '/verify_otp', to: 'registrations#verify_otp'

  # Password reset (phone‑based SMS OTP)
  post '/passwords/send_reset_code', to: 'passwords#send_reset_code'
  post '/passwords/reset',           to: 'passwords#reset'

  # Users – welcome endpoint
  patch '/users/welcome', to: 'users#welcome'

  # Filter API
  get 'filters', to: 'api/filters#index'
  get 'homepage', to: 'api/v1/homepage#index'

  get "/test_session", to: "test#session"

  get '/category/:id', to: redirect('/categories/%{id}')

  resource :session
  get '/session', to: 'sessions#show'
  resources :passwords, param: :token
  post "sign_up", to: "registrations#create"

  resources :categories, only: [:index, :show]

  # Products
  resources :products, only: [:index, :show, :create, :update, :destroy] do
    member do
      post 'feature'
      get :similar
    end
    collection do
      get 'featured'
      get 'filter_options'
    end
    resources :reports, only: [:create]
  end

  # Packages
  resources :packages, only: [:index, :show, :create, :update, :destroy] do
    collection do
      get :filter_options
    end
  end

  # Cart & Wishlist
  resource :cart, only: [:show] do
    post :add_item
    post :add_items   # ★ NEW: batch multi‑variant add
    patch :update_item
    delete 'remove_item/:id', to: 'carts#remove_item', as: :remove_item
    post :merge
  end
  resource :wishlist, only: [:show] do
    post :add_item
    delete 'remove_item/:id', to: 'wishlists#remove_item', as: :remove_item
    post :merge
  end

  resource :vendor_subscription, only: [:create, :destroy]

  resources :recently_viewed, only: [:index, :create]
  resources :comparisons, only: [:index, :create, :destroy]

  resources :price_alerts, only: [:index, :create, :destroy]

  # Reviews, Q&A
  resources :reviews, only: [:create, :update, :destroy]
  get '/products/:product_id/reviews', to: 'reviews#index'
  get '/vendors/:vendor_id/reviews', to: 'reviews#index'
  get '/packages/:package_id/reviews', to: 'reviews#index'
  resources :questions, only: [:index, :create] do
    resources :answers, only: [:create]
  end

  # Returns, bulk orders, messages
  resources :return_requests, only: [:index, :create, :update, :show] do
    member do
      post :approve   # public seller/admin approve
      post :reject    # public seller/admin reject
    end
  end
  resources :bulk_orders, only: [:create, :index]
  resources :messages, only: [:index, :create]
  get 'conversations', to: 'messages#conversations'

  get 'shipping_rates/calculate', to: 'shipping_rates#calculate'

  # Geocoding
  get  'geocode/reverse',         to: 'geocode#reverse'
  get  'geocode/search',          to: 'geocode#search'
  get  'geocode/suggest',         to: 'geocode#suggest'
  post 'geocode/validate_place',  to: 'geocode#validate_place'

  get 'shipping_estimate', to: 'shipping_estimate#show'

  # Webhooks
  post 'webhooks/payments',   to: 'webhooks/payments#create'
  post 'webhooks/telebirr',   to: 'webhooks/telebirr#create'

  # Manifest public view
  get 'manifest/:id', to: 'manifests#show', as: :manifest

  # ─── API V1 (mobile & public) ────────────────────────
  namespace :api do
    # Delivery partner actions (legacy)
    post 'delivery/verify_pin', to: 'delivery#verify_pin'
    post 'delivery/update_location', to: 'delivery#update_location'

    # Seller verification
    post 'seller_verification', to: 'seller_verification#create'

    namespace :v1 do
      get 'homepage', to: 'homepage#index'

      # ★ Recently Viewed (logged-in users)
      resources :recently_vieweds, only: [:index, :create]

      get 'vendors/me', to: 'vendors#me'
      put 'vendors/me', to: 'vendors#update_me'

      resources :vendors, only: [:index, :show] do
        member do
          get :filter_options
        end
        resources :reviews, only: [:index, :create], controller: 'vendor_reviews'
      end
      resources :products, only: [:index]
      resources :collections, only: [:index, :show]
      resources :membership_plans, only: [:index]
      get 'suggestions', to: 'suggestions#index'
      get 'search', to: 'search#index'
      get 'search/suggest_correction', to: 'search#suggest_correction'
      get 'buyer_central', to: 'buyer_central#index'
      resources :saved_searches, only: [:index, :create, :destroy]
      get 'popular_searches', to: 'popular_searches#index'
      patch 'profile', to: 'profiles#update'
      post 'verify-location', to: 'profiles#verify_location'

      # ★ FCM token management (mobile push)
      patch  'profile/fcm_token',  to: 'profiles#update_fcm_token'
      delete 'profile/fcm_token',  to: 'profiles#clear_fcm_token'

      resources :banners, only: [:index]
      resources :promotional_sections, only: [:index]
      resources :announcements, only: [:index]

      resources :notifications, only: [:index, :show] do
        member { patch :read }
        collection do
          get :unread_count
          post :mark_all_read
        end
      end

      resources :payment_gateways, only: [:index]

      # ★ Partner Board (for logistics companies)
      get  'partner_board', to: 'partner_board#index'
      post 'partner_board/:id/accept', to: 'partner_board#accept'

      # ★ Partner‑facing endpoints (own data)
      get    'partner/profile',           to: 'partner/profile#show'
      patch  'partner/profile',           to: 'partner/profile#update'
      patch  'partner/toggle_online',     to: 'partner/profile#toggle_online'
      patch  'partner/profile_image',     to: 'partner/profile#update_image'
      get    'partner/vehicles',          to: 'partner/vehicles#index'
      post   'partner/vehicles',          to: 'partner/vehicles#create'
      patch  'partner/vehicles/:id',      to: 'partner/vehicles#update'
      delete 'partner/vehicles/:id',      to: 'partner/vehicles#destroy'
      get    'partner/rate_cards',        to: 'partner/rate_cards#index'
      get    'partner/active_deliveries', to: 'partner/deliveries#active'
      patch  'partner/active_deliveries/:id/update_status', to: 'partner/deliveries#update_status'
      # ★ NEW: Partner financial summary
      get    'partner/financials',        to: 'partner/financials#show'

      # ★ NEW: Partner drivers management
      get    'partner/drivers',          to: 'partner/drivers#index'
      post   'partner/drivers',          to: 'partner/drivers#create'
      patch  'partner/drivers/:id',      to: 'partner/drivers#update'
      delete 'partner/drivers/:id',      to: 'partner/drivers#destroy'

      # ★ Public driver verification (no auth)
      post 'delivery_verifications/verify_pin', to: 'delivery_verifications#verify_pin'

      # ★ Delivery Verifications (seller, driver, buyer, admin)
      post 'delivery_verifications/:delivery_request_id/seller_confirm',   to: 'delivery_verifications#seller_confirm'
      post 'delivery_verifications/:delivery_request_id/driver_picked_up', to: 'delivery_verifications#driver_picked_up'
      post 'delivery_verifications/:delivery_request_id/driver_delivered', to: 'delivery_verifications#driver_delivered'
      post 'delivery_verifications/:delivery_request_id/buyer_confirm',    to: 'delivery_verifications#buyer_confirm'
      post 'delivery_verifications/:delivery_request_id/admin_verify_cod', to: 'delivery_verifications#admin_verify_cod'
    end
  end

  # ═══ Admin namespace ═══
  namespace :admin do
    get 'dashboard', to: 'dashboard#index'
    get 'stats', to: 'dashboard#stats'
    resources :categories
    resources :vendors, only: [:index, :show, :destroy] do
      member do
        patch :approve
        patch :reject
        patch :suspend
        patch :unsuspend
        post :toggle_featured
        post :assign_membership
      end
    end
    resources :regions
    resources :zones
    resources :woredas
    resources :shipping_rates

    resources :payouts, only: [:index, :create, :update] do
      collection do
        post :bulk_process_telebirr
        get  :bulk_bank_export
      end
      member do
        post :approve
        post :reject
        post :mark_completed
        post :mark_processing
        post :retry_telebirr
      end
    end

    resources :membership_plans
    resources :carousel_items
    resources :coupons, only: [:index, :create, :update, :destroy]
    resources :users, only: [:index, :update, :destroy]
    resources :products, only: [:index, :show, :update, :destroy]
    resources :packages, only: [:index, :show, :update, :destroy]
    resources :orders, only: [:index, :show] do
      member do
        patch :update_status
      end
    end
    resources :announcements, only: [:index, :create, :update, :destroy]
    resources :disputes, only: [:index, :update]
    resources :reports, only: [:index]
    resources :hero_banners do
      collection { post :reorder }
    end
    resources :promotional_sections do
      member { post :refresh_products }
    end
    resources :collections do
      member { post :refresh_products }
    end
    resources :product_attributes

    # ★ Logistics partners with nested vehicles, drivers, rate cards
    resources :logistics_partners do
      collection do
        get :cod_balance
        get :cod_details
      end
      member do
        patch :reconcile_order
      end
      resources :vehicles, only: [:index, :create, :update, :destroy], controller: 'logistics_partners/vehicles'
      resources :drivers, only: [:index, :create, :update, :destroy], controller: 'logistics_partners/drivers'
      resources :rate_cards, only: [:index, :create, :update, :destroy], controller: 'logistics_partners/rate_cards'
    end

    resources :payment_gateway_configs, path: 'payment-gateways', only: [:index, :show, :create, :update, :destroy]
    resources :return_requests, only: [:index, :show, :update] do
      member do
        post :approve
        post :reject
        post :mark_received
        post :complete
      end
    end

    resources :return_policies, only: [:index, :show, :create, :update, :destroy]
    resources :legal_pages, only: [:index, :show, :create, :update, :destroy]

    resources :manual_dispatches, only: [:index, :show] do
      member do
        patch :assign
        patch :update_status
        post :notes
        post :evidence
      end
    end

    resources :partner_payouts, only: [:index, :show]
    resources :financial_ledgers, only: [:index]

    # ★ Delivery Requests management (admin)
    resources :delivery_requests, only: [:index] do
      collection do
        get :active
      end
      member do
        patch :assign
        patch :cancel
        patch :reassign
      end
    end

    # ★ Logistics global settings (rate cards, thresholds)
    resource :logistics_settings, only: [:show, :update], controller: 'logistics_settings'

    # ★ NEW: Sub-admins management
    resources :sub_admins, only: [:index, :show, :create, :update, :destroy]

    get  'settings', to: 'settings#index'
    patch 'settings', to: 'settings#update'
  end

  # ═══ Seller namespace ═══
  namespace :seller do
    get 'dashboard', to: 'dashboard#index'
    post 'toggle_shop', to: 'dashboard#toggle_shop'
    resources :stats, only: [:index]
    resources :payouts, only: [:index, :create]
    resources :orders, only: [:index, :show] do
      member do
        post :accept
        post :reject
        patch :status, to: 'orders#update_status'
      end
    end
    resources :packages, only: [:index, :show, :create, :update, :destroy]
  end

  get 'carousel', to: 'home#carousel'
  get 'stats', to: 'stats#index'

  # Frontend catch‑all
  unless Rails.env.production?
    # Development: no catch‑all
  else
    root 'frontend#index'
    get '*path', to: 'frontend#index', constraints: ->(req) { req.format.html? }
  end
end