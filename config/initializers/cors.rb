Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'localhost:5173',        # React dev
            'localhost:3000',        # Flutter web dev
            '127.0.0.1:5173',
            '127.0.0.1:3000',
            '10.0.2.2:3000'          # Android emulator

    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end

  # In production, replace the above with your actual domain(s):
  # allow do
  #   origins 'your-production-domain.com', 'www.your-production-domain.com'
  #   resource '*', ... same as above
  # end
end