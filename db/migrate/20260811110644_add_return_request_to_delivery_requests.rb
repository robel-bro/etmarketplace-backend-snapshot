class AddReturnRequestToDeliveryRequests < ActiveRecord::Migration[8.1]
  def change
    add_reference :delivery_requests, :return_request, null: true, foreign_key: true
  end
end