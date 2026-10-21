class AddPricingFieldsToLogisticsPartners < ActiveRecord::Migration[8.1]
  def change
    add_column :logistics_partners, :description, :string unless column_exists?(:logistics_partners, :description)
    add_column :logistics_partners, :base_rate, :decimal, precision: 10, scale: 2, default: 0 unless column_exists?(:logistics_partners, :base_rate)
    add_column :logistics_partners, :per_km_rate, :decimal, precision: 10, scale: 2, default: 0 unless column_exists?(:logistics_partners, :per_km_rate)
    add_column :logistics_partners, :min_charge, :decimal, precision: 10, scale: 2, default: 0 unless column_exists?(:logistics_partners, :min_charge)
    add_column :logistics_partners, :delivery_speed, :integer, default: 0 unless column_exists?(:logistics_partners, :delivery_speed)
    add_column :logistics_partners, :estimated_days, :integer, default: 1 unless column_exists?(:logistics_partners, :estimated_days)
  end
end
