class AddPhoneToLogisticsPartners < ActiveRecord::Migration[7.1]
  def change
    add_column :logistics_partners, :phone, :string
  end
end