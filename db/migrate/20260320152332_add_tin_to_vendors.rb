class AddTinToVendors < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:vendors, :tin)
      add_column :vendors, :tin, :string
    end
  end
end
