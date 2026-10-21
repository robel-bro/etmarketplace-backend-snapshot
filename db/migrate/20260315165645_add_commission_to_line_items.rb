class AddCommissionToLineItems < ActiveRecord::Migration[8.1]
  def change
    add_column :line_items, :commission_rate, :decimal, precision: 5, scale: 2
    add_column :line_items, :commission_amount, :decimal, precision: 10, scale: 2
  end
end
