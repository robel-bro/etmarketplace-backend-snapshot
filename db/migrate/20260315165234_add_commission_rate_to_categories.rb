class AddCommissionRateToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :commission_rate, :decimal, precision: 5, scale: 2
  end
end
