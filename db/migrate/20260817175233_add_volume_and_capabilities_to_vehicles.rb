class AddVolumeAndCapabilitiesToVehicles < ActiveRecord::Migration[8.1]
  def up
    # Add max_volume_cm3 only if it doesn't exist
    unless column_exists?(:vehicles, :max_volume_cm3)
      add_column :vehicles, :max_volume_cm3, :decimal, precision: 12, scale: 2
    end

    # refrigerated and fragile_capable already exist, so we skip adding them here.
  end

  def down
    # If you need to rollback, remove max_volume_cm3 only if it exists
    remove_column :vehicles, :max_volume_cm3 if column_exists?(:vehicles, :max_volume_cm3)
  end
end