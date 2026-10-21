class AddLogisticsPartnerToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :logistics_partner, null: true, foreign_key: true
  end
end