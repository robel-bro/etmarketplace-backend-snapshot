class AddIsHotDealToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :is_hot_deal, :boolean, default: false
  end
end