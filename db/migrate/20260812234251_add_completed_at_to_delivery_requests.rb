class AddCompletedAtToDeliveryRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :delivery_requests, :completed_at, :datetime
  end
end