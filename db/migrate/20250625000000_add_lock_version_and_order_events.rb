class AddLockVersionAndOrderEvents < ActiveRecord::Migration[8.1]
  def change
    # Optimistic locking column
    add_column :orders, :lock_version, :integer, default: 0, null: false

    # Audit log for orders
    create_table :order_events do |t|
      t.references :order, null: false, foreign_key: true
      t.string :event_type, null: false
      t.references :actor, polymorphic: true
      t.string :status_from
      t.string :status_to
      t.timestamps
    end

    add_index :order_events, :event_type
  end
end
