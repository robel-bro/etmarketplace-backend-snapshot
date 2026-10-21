class ConsolidatedDeliveryFields < ActiveRecord::Migration[8.1]
  def change
    # ----- Logistics Partners -----
    add_column :logistics_partners, :dispatch_mode, :integer, default: 0, null: false
    # 0 = manual, 1 = external_api, 2 = internal_fleet
    add_column :logistics_partners, :remittance_required, :boolean, default: false
    add_column :logistics_partners, :return_fee, :decimal, precision: 10, scale: 2, default: 0

    # ----- Orders -----
    add_column :orders, :checkout_group_id, :string, limit: 36
    add_index :orders, :checkout_group_id

    # ----- Delivery Requests -----
    add_column :delivery_requests, :pickup_points, :jsonb, default: []
    add_column :delivery_requests, :manifest_url, :string
    add_column :delivery_requests, :evidence, :jsonb, default: []
    add_column :delivery_requests, :consolidated_shipping_cost, :decimal, precision: 10, scale: 2
    add_column :delivery_requests, :total_subsidy, :decimal, precision: 10, scale: 2, default: 0
    add_column :delivery_requests, :buyer_shipping_cost, :decimal, precision: 10, scale: 2

    # ----- Products -----
    add_column :products, :weight_kg, :decimal, precision: 8, scale: 3
    add_column :products, :length_cm, :decimal, precision: 6, scale: 1
    add_column :products, :width_cm, :decimal, precision: 6, scale: 1
    add_column :products, :height_cm, :decimal, precision: 6, scale: 1

    # ----- Vendors -----
    add_column :vendors, :pickup_ready, :boolean, default: false
    add_column :vendors, :preparation_time_minutes, :integer, default: 60
    add_column :vendors, :pickup_ready_deadline, :datetime

    # ----- Checkout Groups -----
    create_table :checkout_groups do |t|
      t.references :user, null: false, foreign_key: true
      t.decimal :consolidated_shipping_cost, precision: 10, scale: 2
      t.decimal :buyer_shipping_cost, precision: 10, scale: 2
      t.decimal :total_subsidy, precision: 10, scale: 2, default: 0
      t.decimal :platform_markup, precision: 10, scale: 2, default: 0
      t.integer :status, default: 0, null: false
      t.timestamps
    end

    # ----- Manual Dispatches -----
    create_table :manual_dispatches do |t|
      t.references :delivery_request, null: false, foreign_key: true
      t.references :admin_user, foreign_key: { to_table: :users }
      t.references :logistics_partner, foreign_key: true
      t.integer :status, default: 0, null: false
      t.text :notes
      t.timestamps
    end
  end
end