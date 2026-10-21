class AddPartnerFinancialAndRegionFieldsToLogisticsPartners < ActiveRecord::Migration[8.1]
  def change
    add_column :logistics_partners, :bank_name, :string
    add_column :logistics_partners, :account_number, :string
    add_column :logistics_partners, :telebirr_number, :string
    add_column :logistics_partners, :operating_region, :string
  end
end
