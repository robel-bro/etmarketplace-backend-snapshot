class AddBulkFieldsToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :bulk_enabled, :boolean, default: false, null: false
    add_column :products, :minimum_bulk_quantity, :integer, default: 1, null: false
  end
end