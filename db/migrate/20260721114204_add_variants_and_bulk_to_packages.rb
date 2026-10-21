class AddVariantsAndBulkToPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :packages, :variants_data, :jsonb
    add_column :packages, :bulk_enabled, :boolean
  end
end
