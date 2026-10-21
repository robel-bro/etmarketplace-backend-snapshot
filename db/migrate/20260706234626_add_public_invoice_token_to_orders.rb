class AddPublicInvoiceTokenToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :public_invoice_token, :string
    add_index :orders, :public_invoice_token
  end
end
