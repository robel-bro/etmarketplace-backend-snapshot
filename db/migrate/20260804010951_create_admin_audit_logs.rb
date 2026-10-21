class CreateAdminAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_audit_logs do |t|
      t.references :admin_user, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.references :auditable, polymorphic: true, null: true
      t.jsonb :metadata, default: {}
      t.string :ip_address
      t.timestamps
    end
  end
end