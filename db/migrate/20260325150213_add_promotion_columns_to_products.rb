class AddPromotionColumnsToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :is_flash_sale, :boolean, default: false
    add_column :products, :flash_sale_price, :decimal, precision: 10, scale: 2
    add_column :products, :flash_sale_ends_at, :datetime
    add_column :products, :is_super_deal, :boolean, default: false
    add_column :products, :super_deal_price, :decimal, precision: 10, scale: 2
    add_column :products, :super_deal_ends_at, :datetime
    add_column :products, :views_count, :integer, default: 0
    add_column :products, :sold_count, :integer, default: 0
    add_column :products, :is_trending, :boolean, default: false
  end
end
