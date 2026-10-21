# app/services/notification_service.rb

class NotificationService
  # Send a notification to a user via all configured channels.
  # This method NEVER raises, ensuring it won't rollback the caller's transaction.
  def self.notify(user, type, metadata = {})
    return unless user

    title, body, enriched_metadata, priority = build_notification(type, metadata, user)

    # 1. In‑app notification (stored in DB)
    if defined?(Notification) && user.respond_to?(:notifications)
      begin
        user.notifications.create!(
          title: title,
          body: body,
          notification_type: type.to_s,
          metadata: enriched_metadata
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "[NotificationService] In‑app creation failed: #{e.message}"
      end
    end

    # 2. Push notification (Firebase) – background job
    if user.fcm_token.present?
      PushNotificationJob.perform_later(
        user.id, title, body, enriched_metadata, priority
      )
    end

    # 3. Email – background job
    if user.email.present? && email_enabled_for?(type)
      begin
        NotificationMailer.with(
          user: user, title: title, body: body, type: type
        ).notify.deliver_later
      rescue => e
        Rails.logger.error "[NotificationService] Email enqueue failed: #{e.message}"
      end
    end

    # 4. SMS – background job (not synchronous)
    if user.phone.present? && sms_enabled_for?(type)
      SmsNotificationJob.perform_later(user.phone, "#{title}: #{body}")
    end
  end

  # Admin notification – broadcast via ActionCable
  def self.notify_admin(event_type, payload)
    Rails.logger.info "[AdminNotification] #{event_type}: #{payload.inspect}"
    ActionCable.server.broadcast(
      'admin_notifications',
      { type: event_type, payload: payload }
    )
  rescue => e
    Rails.logger.error "[AdminNotification] Failed to broadcast: #{e.message}"
  end

  private

  def self.build_notification(type, metadata, user)
    type = type.to_s

    # ✅ Personalised greeting with user's name
    recipient_name = user.full_name.presence || user.phone.presence || 'Customer'
    recipient_type = if user.vendor.present?
                       "Dear #{recipient_name} (Seller)"
                     elsif user.logistics_partner.present?
                       "Dear #{recipient_name} (Partner)"
                     else
                       "Dear #{recipient_name}"
                     end

    case type
    when "order_placed"
      order_id = metadata[:order_id]
      total    = metadata[:total]
      [
        "Order Confirmed",
        "#{recipient_type}, your order ##{order_id} for ETB #{format_price(total)} has been placed successfully.",
        { order_id: order_id, deep_link: "/orders/#{order_id}" },
        'normal'
      ]

    when "new_order"
      order_id     = metadata[:order_id]
      product_name = metadata[:product_name]
      [
        "New Order Received",
        "#{recipient_type}, you have a new order ##{order_id} – #{product_name}.",
        { order_id: order_id, product_name: product_name, deep_link: "/seller/orders/#{order_id}" },
        'high'
      ]

    when "order_acceptance_reminder"
      order_id = metadata[:order_id]
      deadline = metadata[:minutes_left]
      [
        "Reminder: Accept Order ##{order_id}",
        "#{recipient_type}, you have #{deadline} minutes left to accept or reject order ##{order_id}.",
        { order_id: order_id, deadline: deadline, deep_link: "/seller/orders/#{order_id}" },
        'high'
      ]

    when "order_accepted"
      order_id = metadata[:order_id]
      [
        "Order Accepted",
        "#{recipient_type}, great news! Your order ##{order_id} has been accepted.",
        { order_id: order_id, deep_link: "/orders/#{order_id}" },
        'normal'
      ]

    # ★ NEW: Seller accepts order, but no partner assigned yet
    when "order_accepted_seller"
      order_id = metadata[:order_id]
      [
        "Order Accepted",
        "#{recipient_type}, order ##{order_id} has been accepted. Waiting for a delivery partner to accept the job.",
        { order_id: order_id, deep_link: "/seller/orders/#{order_id}" },
        'normal'
      ]

    when "order_rejected_by_seller"
      order_id = metadata[:order_id]
      [
        "Order Cancelled",
        "#{recipient_type}, your order ##{order_id} was cancelled by the seller.",
        { order_id: order_id, deep_link: "/orders/#{order_id}" },
        'normal'
      ]

    when "order_auto_cancelled"
      order_id = metadata[:order_id]
      [
        "Order Expired",
        "#{recipient_type}, order ##{order_id} was cancelled – seller didn't respond in time.",
        { order_id: order_id, deep_link: "/orders/#{order_id}" },
        'normal'
      ]

    when "order_auto_cancelled_seller"
      order_id = metadata[:order_id]
      [
        "Order Expired",
        "#{recipient_type}, order ##{order_id} was cancelled because you didn't respond in time.",
        { order_id: order_id, deep_link: "/seller/orders/#{order_id}" },
        'high'
      ]

    when "shipment_created"
      order_id   = metadata[:order_id]
      carrier    = metadata[:carrier]
      tracking   = metadata[:tracking_number]
      [
        "Order Shipped",
        "#{recipient_type}, your order ##{order_id} has been shipped via #{carrier}. Tracking: #{tracking || 'N/A'}",
        { order_id: order_id, carrier: carrier, tracking_number: tracking, deep_link: "/orders/#{order_id}" },
        'normal'
      ]

    when "shipment_updated"
      order_id   = metadata[:order_id]
      status     = metadata[:status].to_s.humanize
      [
        "Shipment Update",
        "#{recipient_type}, your order ##{order_id} status updated to: #{status}.",
        { order_id: order_id, status: status, deep_link: "/orders/#{order_id}" },
        'normal'
      ]

    when "delivery_accepted"
      order_id = metadata[:order_id]
      [
        "Delivery Accepted",
        "#{recipient_type}, your order ##{order_id} has been accepted by a delivery partner.",
        { order_id: order_id, deep_link: "/orders/#{order_id}" },
        'normal'
      ]

    when "delivery_accepted_seller"
      order_id = metadata[:order_id]
      [
        "Delivery Partner Assigned",
        "#{recipient_type}, a delivery partner has accepted order ##{order_id}.",
        { order_id: order_id, deep_link: "/seller/orders/#{order_id}" },
        'normal'
      ]

    when "delivery_pin"
      order_id = metadata[:order_id]
      pin      = metadata[:delivery_pin]
      [
        "Delivery PIN",
        "#{recipient_type}, your delivery PIN for order ##{order_id} is: #{pin}",
        { order_id: order_id, delivery_pin: pin, deep_link: "/orders/#{order_id}" },
        'high'
      ]

    when "order_delivered"
      order_id = metadata[:order_id]
      [
        "Order Delivered",
        "#{recipient_type}, your order ##{order_id} has been delivered successfully. Thank you for shopping with ET Marketplace!",
        { order_id: order_id, deep_link: "/orders/#{order_id}" },
        'normal'
      ]

    when "order_delivered_seller"
      order_id = metadata[:order_id]
      [
        "Order Delivered",
        "#{recipient_type}, order ##{order_id} has been delivered successfully.",
        { order_id: order_id, deep_link: "/seller/orders/#{order_id}" },
        'normal'
      ]

    # ★ NEW: Driver assigned notifications
    when "driver_assigned_to_seller"
      order_id = metadata[:order_id]
      driver_name = metadata[:driver_name] || 'Driver'
      vehicle_plate = metadata[:vehicle_plate] || 'N/A'
      company_name = metadata[:logistics_company_name] || 'Logistics Partner'
      [
        "Driver Assigned",
        "#{recipient_type}, driver #{driver_name} (#{vehicle_plate}) from #{company_name} will pick up your order ##{order_id}.",
        {
          order_id: order_id,
          driver_name: driver_name,
          driver_phone: metadata[:driver_phone],
          driver_photo_url: metadata[:driver_photo_url],
          vehicle_plate: vehicle_plate,
          vehicle_type: metadata[:vehicle_type],
          logistics_company_name: company_name,
          deep_link: "/seller/orders/#{order_id}"
        },
        'high'
      ]

    when "driver_assigned_to_buyer"
      order_id = metadata[:order_id]
      driver_name = metadata[:driver_name] || 'Driver'
      vehicle_plate = metadata[:vehicle_plate] || 'N/A'
      company_name = metadata[:logistics_company_name] || 'Logistics Partner'
      [
        "Your Delivery Driver",
        "#{recipient_type}, driver #{driver_name} (#{vehicle_plate}) from #{company_name} is assigned to deliver your order ##{order_id}.",
        {
          order_id: order_id,
          driver_name: driver_name,
          driver_phone: metadata[:driver_phone],
          driver_photo_url: metadata[:driver_photo_url],
          vehicle_plate: vehicle_plate,
          vehicle_type: metadata[:vehicle_type],
          logistics_company_name: company_name,
          deep_link: "/orders/#{order_id}"
        },
        'high'
      ]

    when "return_approved"
      return_id = metadata[:return_id]
      reason    = metadata[:reason]
      [
        "Return Approved",
        "#{recipient_type}, your return request ##{return_id} has been approved. Reason: #{reason}",
        { return_id: return_id, deep_link: "/returns/#{return_id}" },
        'normal'
      ]

    when "return_approved_seller"
      return_id = metadata[:return_id]
      order_id  = metadata[:order_id]
      [
        "Return Approved",
        "#{recipient_type}, return request ##{return_id} for order ##{order_id} has been approved.",
        { return_id: return_id, order_id: order_id, deep_link: "/seller/orders/#{order_id}" },
        'normal'
      ]

    when "return_rejected"
      return_id = metadata[:return_id]
      reason    = metadata[:reason].presence || 'No reason provided'
      [
        "Return Rejected",
        "#{recipient_type}, your return request ##{return_id} was rejected. Reason: #{reason}",
        { return_id: return_id, deep_link: "/returns/#{return_id}" },
        'normal'
      ]

    when "return_completed"
      return_id = metadata[:return_id]
      amount    = metadata[:refund_amount]
      [
        "Return Completed",
        "#{recipient_type}, return request ##{return_id} has been completed. Refund amount: ETB #{format_price(amount)}",
        { return_id: return_id, deep_link: "/returns/#{return_id}" },
        'high'
      ]

    when "return_completed_seller"
      return_id = metadata[:return_id]
      [
        "Return Completed",
        "#{recipient_type}, return request ##{return_id} has been completed.",
        { return_id: return_id, deep_link: "/seller/returns/#{return_id}" },
        'normal'
      ]

    when "payout_paid"
      amount = metadata[:amount]
      [
        "Payout Processed",
        "#{recipient_type}, your payout of ETB #{format_price(amount)} has been approved.",
        { amount: amount },
        'normal'
      ]

    when "vendor_approved"
      [
        "Seller Application Approved",
        "#{recipient_type}, congratulations! Your seller application has been approved.",
        { deep_link: "/seller" },
        'high'
      ]

    when "vendor_rejected"
      reason = metadata[:reason].presence || "No reason provided"
      [
        "Seller Application Rejected",
        "#{recipient_type}, your seller application was not approved. Reason: #{reason}",
        { reason: reason },
        'normal'
      ]

    when "flash_deal_started"
      deal_title = metadata[:title]
      discount   = metadata[:discount]
      [
        "Flash Deal Live!",
        "#{recipient_type}, #{deal_title} is now live with #{discount}% off.",
        { deep_link: "/flash-deals" },
        'normal'
      ]

    when "price_drop_alert"
      product_name = metadata[:product_name]
      new_price    = metadata[:new_price]
      old_price    = metadata[:original_price]
      discount     = metadata[:discount_percentage]
      image_url    = metadata[:image_url]

      body = "ETB #{format_price(new_price)} – #{discount}% off from ETB #{format_price(old_price)}"

      [
        "Price Drop: #{product_name}",
        "#{recipient_type}, #{body}",
        {
          product_id:           metadata[:product_id],
          product_name:         product_name,
          new_price:            new_price,
          original_price:       old_price,
          discount_percentage:  discount,
          image_url:            image_url,
          deep_link:            "/products/#{metadata[:product_id]}"
        },
        'normal'
      ]

    else
      # Polite fallback for any missing type – never show raw hash
      safe_metadata = metadata.is_a?(Hash) ? metadata : {}
      ["Notification", "#{recipient_type}, #{safe_metadata[:message].presence || 'you have a new update.'}", safe_metadata, 'normal']
    end
  end

  def self.email_enabled_for?(type)
    %w[
      order_placed
      order_accepted
      order_accepted_seller
      order_rejected_by_seller
      order_auto_cancelled
      vendor_approved
      vendor_rejected
      payout_paid
      price_drop_alert
      return_approved
      return_rejected
      return_completed
      driver_assigned_to_seller
      driver_assigned_to_buyer
    ].include?(type.to_s)
  end

  def self.sms_enabled_for?(type)
    %w[
      new_order
      order_acceptance_reminder
      order_auto_cancelled_seller
      vendor_approved
      delivery_pin
      order_placed
      order_accepted_seller
      return_approved
      return_rejected
      return_completed
      driver_assigned_to_seller
      driver_assigned_to_buyer
    ].include?(type.to_s)
  end

  def self.format_price(value)
    return '0.00' if value.blank?
    sprintf('%.2f', value)
  end
end