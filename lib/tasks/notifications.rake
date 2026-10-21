namespace :notifications do
  desc "Send promotional notifications to all buyers (flash, super, hot, new arrivals)"
  task send_promotions: :environment do
    # Safety check – don't run twice on the same day
    if Notification.where(notification_type: ['flash_deal', 'super_deal', 'hot_deal', 'new_arrival'])
                   .where('created_at > ?', Date.today).exists?
      puts "Promotions already sent today. Exiting."
      next
    end

    flash = Product.where(is_flash_sale: true)
                   .where('flash_sale_ends_at > ?', Time.current)
                   .order('discount DESC')
                   .limit(2)
    super_deals = Product.where(is_super_deal: true)
                         .where('super_deal_ends_at > ?', Time.current)
                         .order('discount DESC')
                         .limit(2)
    hot = Product.where('stock > 0 AND sold_count > 0')
                 .order('sold_count DESC')
                 .limit(2)
    new_arrivals = Product.where('created_at > ?', 7.days.ago)
                          .order('created_at DESC')
                          .limit(2)

    promotions = []
    promotions += flash.map { |p| { type: 'flash_deal', product: p } }
    promotions += super_deals.map { |p| { type: 'super_deal', product: p } }
    promotions += hot.map { |p| { type: 'hot_deal', product: p } }
    promotions += new_arrivals.map { |p| { type: 'new_arrival', product: p } }

    buyer_ids = User.left_joins(:vendor).where(vendors: { id: nil }).pluck(:id)

    buyer_ids.each do |user_id|
      user = User.find(user_id)
      promotions.each do |promo|
        product = promo[:product]
        image_url = product.images.attached? ? Rails.application.routes.url_helpers.url_for(product.images.first) : nil
        user.notifications.create!(
          title: promo_title(promo[:type], product.title),
          body: "Get it now at ETB #{product.price.to_f}",
          notification_type: promo[:type],
          metadata: {
            product_id: product.id,
            image_url: image_url
          }
        )
      end
    end

    puts "Promotional notifications sent to #{buyer_ids.size} buyers."
  end

  def promo_title(type, product_name)
    case type
    when 'flash_deal' then "⚡ Flash Deal: #{product_name}"
    when 'super_deal' then "🌟 Super Deal: #{product_name}"
    when 'hot_deal'    then "🔥 Hot Deal: #{product_name}"
    when 'new_arrival' then "🆕 New Arrival: #{product_name}"
    else product_name
    end
  end
end