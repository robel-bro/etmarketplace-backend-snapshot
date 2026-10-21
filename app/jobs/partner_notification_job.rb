class PartnerNotificationJob < ApplicationJob
  queue_as :default

  def perform(partner_id, delivery_request_id)
    partner = LogisticsPartner.find(partner_id)
    delivery_request = DeliveryRequest.find(delivery_request_id)

    # TODO: Replace with real HTTP call to partner's API endpoint
    Rails.logger.info "Notifying partner #{partner.name} about DR ##{delivery_request.id}"
    # Example HTTP call:
    # HTTParty.post(partner.api_endpoint, body: delivery_request_json(delivery_request).to_json, headers: { 'Authorization' => "Bearer #{partner.api_key}" })
  end
end