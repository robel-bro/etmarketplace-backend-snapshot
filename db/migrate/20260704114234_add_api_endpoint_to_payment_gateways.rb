class AddApiEndpointToPaymentGateways < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_gateways, :api_endpoint, :string
  end
end
