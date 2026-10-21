class AddReturnFields < ActiveRecord::Migration[8.1]
  def change
    add_column :return_requests, :liability, :string, default: 'buyer' unless column_exists?(:return_requests, :liability)
    add_column :return_requests, :return_shipping_cost, :decimal, precision: 10, scale: 2 unless column_exists?(:return_requests, :return_shipping_cost)
    add_column :return_requests, :return_tracking_number, :string unless column_exists?(:return_requests, :return_tracking_number)
    add_column :return_requests, :received_at, :datetime unless column_exists?(:return_requests, :received_at)
    add_column :return_requests, :admin_notes, :text unless column_exists?(:return_requests, :admin_notes)
  end
end
