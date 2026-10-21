class RemoveNotNullConstraintFromUsersEmailAddressOld < ActiveRecord::Migration[7.1]
  def change
    change_column_null :users, :email_address_old, true
  end
end