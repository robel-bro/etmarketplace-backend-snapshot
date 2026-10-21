class AddCommissionRateToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :commission_rate, :decimal, precision: 5, scale: 2
  end
end
