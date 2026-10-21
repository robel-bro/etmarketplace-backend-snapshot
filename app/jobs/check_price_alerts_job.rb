class CheckPriceAlertsJob < ApplicationJob
  queue_as :default

  def perform
    PriceAlert.where(alert_sent: [false, nil]).find_each do |alert|
      product = alert.product
      next unless product

      if product.price <= alert.target_price
        NotificationService.notify(alert.user, :price_drop_alert, {
          product_id:           product.id,
          product_name:         product.title,
          new_price:            product.price,
          original_price:       product.original_price,
          discount_percentage:  product.discount_percentage,
          image_url:            product.first_image_url,
          deep_link:            "/products/#{product.id}"
        })
        alert.update(alert_sent: true)
      end
    end
  end
end