class AddFeaturesToPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :packages, :features, :jsonb
  end
end
