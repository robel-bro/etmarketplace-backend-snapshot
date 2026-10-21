class AddCompanyFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :company_name, :string
    add_column :users, :tax_id, :string
  end
end
