class AddCheckoutGroupToDeliveryRequests < ActiveRecord::Migration[8.1]
  def change
    add_reference :delivery_requests, :checkout_group, foreign_key: true, index: true
  end
end