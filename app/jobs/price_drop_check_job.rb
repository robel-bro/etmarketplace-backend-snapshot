class PriceDropCheckJob < ApplicationJob
  queue_as :default

  def perform
    # Fetch all alerts (no "triggered" flag; we'll delete after notifying)
    alerts = PriceAlert.includes(:product, :user)

    alerts.find_each do |alert|
      product = alert.product
      user = alert.user
      next unless product && user

      current_price = product.current_price
      if current_price && current_price <= alert.target_price
        # Use unified NotificationService – sends in-app, push, and email (if user opted in)
        NotificationService.notify(
          user,
          :price_drop_alert,
          {
            product_id: product.id,
            product_name: product.title,
            new_price: current_price,
            target_price: alert.target_price,
            deep_link: "/products/#{product.id}"
          }
        )
        # Remove the alert so it only fires once
        alert.destroy!
      end
    end
  end
end