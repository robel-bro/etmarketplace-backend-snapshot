class AddRolesAndVerifiedToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :role_mask, :integer
    add_column :users, :verified, :boolean
  end
end
