class AddCodReconciledToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :cod_reconciled, :boolean, default: false, null: false
  end
end
