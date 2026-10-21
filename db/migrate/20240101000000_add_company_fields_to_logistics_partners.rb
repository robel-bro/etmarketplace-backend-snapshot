class AddCompanyFieldsToLogisticsPartners < ActiveRecord::Migration[8.1]
  def change
    change_table :logistics_partners do |t|
      t.string :business_license
      t.string :tin
      t.string :insurance_info
      t.string :address
      # t.string :phone   ← already exists, removed
      t.string :coverage_zones, array: true, default: []
      t.integer :status, default: 0, index: true
      t.boolean :online, default: false
      t.string :contact_person
      t.decimal :commission_rate, precision: 5, scale: 2, default: 0.0
    end
  end
end