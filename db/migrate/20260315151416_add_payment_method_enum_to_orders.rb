class AddPaymentMethodEnumToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :payment_method_enum, :integer, default: 0
  end
end
