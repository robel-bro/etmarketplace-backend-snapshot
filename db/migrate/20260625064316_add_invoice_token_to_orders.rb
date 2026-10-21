class AddInvoiceTokenToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :invoice_token, :string
  end
end
