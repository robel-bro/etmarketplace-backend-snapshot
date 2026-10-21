class AddMissingFieldsToDeliveryRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :delivery_requests, :assigned_at, :datetime unless column_exists?(:delivery_requests, :assigned_at)
    add_column :delivery_requests, :pickup_confirmed_at, :datetime unless column_exists?(:delivery_requests, :pickup_confirmed_at)

    unless column_exists?(:delivery_requests, :cod_status)
      add_column :delivery_requests, :cod_status, :integer, default: 0, null: false
    end

    add_index :delivery_requests, :cod_status unless index_exists?(:delivery_requests, :cod_status)
  end

  def down
    # We won't drop columns here to avoid losing data
    raise ActiveRecord::IrreversibleMigration
  end
end