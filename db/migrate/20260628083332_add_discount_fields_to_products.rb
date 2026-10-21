class AddDiscountFieldsToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :discount_type, :string
    add_column :products, :discount_value, :decimal
  end
end
