class AddTaxColumnsToPayouts < ActiveRecord::Migration[8.1]
  def change
    add_column :payouts, :gross_amount, :decimal, precision: 10, scale: 2, default: 0.0 unless column_exists?(:payouts, :gross_amount)
    add_column :payouts, :tax_withheld, :decimal, precision: 10, scale: 2, default: 0.0 unless column_exists?(:payouts, :tax_withheld)
  end
end