# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_17_212108) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "address_caches", force: :cascade do |t|
    t.string "city"
    t.boolean "corrected", default: false
    t.integer "count", default: 1
    t.datetime "created_at", null: false
    t.string "formatted_address"
    t.string "landmark"
    t.datetime "last_used_at"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "raw_address", null: false
    t.string "source"
    t.string "street"
    t.string "subcity"
    t.datetime "updated_at", null: false
    t.string "woreda"
    t.index ["raw_address"], name: "index_address_caches_on_raw_address", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.string "address_line", null: false
    t.string "building_name"
    t.string "city"
    t.datetime "created_at", null: false
    t.text "delivery_notes"
    t.string "formatted_address"
    t.boolean "is_default", default: false
    t.string "landmark"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "phone"
    t.bigint "region_id", null: false
    t.string "source"
    t.string "street"
    t.string "sub_city"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "woreda_id"
    t.string "woreda_text"
    t.bigint "zone_id"
    t.index ["region_id"], name: "index_addresses_on_region_id"
    t.index ["source"], name: "index_addresses_on_source", where: "((source)::text = 'manual'::text)"
    t.index ["user_id", "is_default"], name: "index_addresses_on_user_id_and_is_default"
    t.index ["user_id"], name: "index_addresses_on_user_id"
    t.index ["woreda_id"], name: "index_addresses_on_woreda_id"
    t.index ["zone_id"], name: "index_addresses_on_zone_id"
  end

  create_table "admin_announcements", force: :cascade do |t|
    t.boolean "active"
    t.string "announcement_type"
    t.text "content"
    t.datetime "created_at", null: false
    t.date "end_date"
    t.string "image"
    t.string "link"
    t.date "start_date"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "admin_audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "admin_user_id", null: false
    t.bigint "auditable_id"
    t.string "auditable_type"
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_admin_audit_logs_on_admin_user_id"
    t.index ["auditable_type", "auditable_id"], name: "index_admin_audit_logs_on_auditable"
  end

  create_table "announcements", force: :cascade do |t|
    t.boolean "active"
    t.text "content"
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "answers", force: :cascade do |t|
    t.text "answer"
    t.datetime "created_at", null: false
    t.bigint "question_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["question_id"], name: "index_answers_on_question_id"
    t.index ["user_id"], name: "index_answers_on_user_id"
  end

  create_table "attribute_values", force: :cascade do |t|
    t.integer "attribute_id"
    t.datetime "created_at", null: false
    t.string "display_value"
    t.datetime "updated_at", null: false
    t.string "value"
  end

  create_table "attributes", force: :cascade do |t|
    t.string "attr_type"
    t.integer "attribute_type"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.boolean "is_filterable"
    t.boolean "is_variant"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "bulk_order_items", force: :cascade do |t|
    t.bigint "bulk_order_id", null: false
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.integer "quantity"
    t.datetime "updated_at", null: false
    t.index ["bulk_order_id"], name: "index_bulk_order_items_on_bulk_order_id"
    t.index ["product_id"], name: "index_bulk_order_items_on_product_id"
  end

  create_table "bulk_orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "status"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_bulk_orders_on_user_id"
  end

  create_table "cart_items", force: :cascade do |t|
    t.decimal "base_price", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "cart_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.integer "package_id"
    t.decimal "price"
    t.bigint "product_id"
    t.integer "quantity"
    t.datetime "updated_at", null: false
    t.jsonb "variant_attributes", default: {}
    t.index ["cart_id", "package_id"], name: "index_cart_items_on_cart_package_unique", unique: true, where: "(product_id IS NULL)"
    t.index ["cart_id", "product_id", "variant_attributes"], name: "index_cart_items_on_cart_product_variant_unique", unique: true, where: "(package_id IS NULL)"
    t.index ["cart_id", "product_id"], name: "index_cart_items_on_cart_id_and_product_id"
    t.index ["cart_id"], name: "index_cart_items_on_cart_id"
    t.index ["expires_at"], name: "index_cart_items_on_expires_at"
    t.index ["product_id"], name: "index_cart_items_on_product_id"
  end

  create_table "carts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_carts_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.json "allowed_attributes", default: []
    t.string "ancestry"
    t.decimal "commission_rate", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.text "description"
    t.string "image"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["ancestry"], name: "index_categories_on_ancestry"
  end

  create_table "category_attributes", force: :cascade do |t|
    t.integer "attribute_id"
    t.integer "category_id"
    t.datetime "created_at", null: false
    t.boolean "is_required"
    t.datetime "updated_at", null: false
  end

  create_table "checkout_groups", force: :cascade do |t|
    t.decimal "buyer_shipping_cost", precision: 10, scale: 2
    t.decimal "consolidated_shipping_cost", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.decimal "platform_markup", precision: 10, scale: 2, default: "0.0"
    t.integer "status", default: 0, null: false
    t.decimal "total_subsidy", precision: 10, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_checkout_groups_on_user_id"
  end

  create_table "collections", force: :cascade do |t|
    t.json "auto_criteria"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "display_order"
    t.datetime "end_date"
    t.boolean "is_active", default: true
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "start_date"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_collections_on_slug", unique: true
  end

  create_table "collections_products", force: :cascade do |t|
    t.bigint "collection_id", null: false
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id"], name: "index_collections_products_on_collection_id"
    t.index ["product_id"], name: "index_collections_products_on_product_id"
  end

  create_table "comparisons", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.jsonb "variant_attributes"
    t.index ["product_id"], name: "index_comparisons_on_product_id"
    t.index ["user_id"], name: "index_comparisons_on_user_id"
  end

  create_table "coupons", force: :cascade do |t|
    t.boolean "active"
    t.string "code"
    t.datetime "created_at", null: false
    t.string "discount_type"
    t.float "discount_value"
    t.date "end_date"
    t.float "min_order_amount"
    t.integer "per_user"
    t.date "start_date"
    t.datetime "updated_at", null: false
    t.integer "usage_limit"
    t.integer "used_count"
  end

  create_table "delivery_requests", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "assigned_at"
    t.decimal "buyer_shipping_cost", precision: 10, scale: 2
    t.bigint "checkout_group_id"
    t.integer "cod_status", default: 0, null: false
    t.datetime "completed_at"
    t.decimal "consolidated_shipping_cost", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.decimal "current_lat", precision: 10, scale: 6
    t.decimal "current_lng", precision: 10, scale: 6
    t.datetime "delivered_at"
    t.string "delivery_address", null: false
    t.decimal "delivery_address_lat", precision: 10, scale: 6
    t.decimal "delivery_address_lng", precision: 10, scale: 6
    t.string "delivery_contact_phone"
    t.decimal "delivery_lat"
    t.decimal "delivery_lng"
    t.bigint "driver_id"
    t.decimal "estimated_cost", precision: 10, scale: 2
    t.jsonb "events", default: []
    t.jsonb "evidence", default: []
    t.bigint "logistics_partner_id"
    t.string "manifest_url"
    t.bigint "order_id", null: false
    t.jsonb "package_details"
    t.datetime "picked_up_at"
    t.string "pickup_address", null: false
    t.datetime "pickup_confirmed_at"
    t.string "pickup_contact_phone"
    t.decimal "pickup_lat"
    t.decimal "pickup_lng"
    t.jsonb "pickup_points", default: []
    t.string "required_vehicle_type"
    t.bigint "return_request_id"
    t.integer "service_level", default: 0, null: false
    t.string "status", default: "pending"
    t.decimal "total_subsidy", precision: 10, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id"
    t.string "vehicle_type"
    t.index ["checkout_group_id"], name: "index_delivery_requests_on_checkout_group_id"
    t.index ["cod_status"], name: "index_delivery_requests_on_cod_status"
    t.index ["driver_id"], name: "index_delivery_requests_on_driver_id"
    t.index ["logistics_partner_id"], name: "index_delivery_requests_on_logistics_partner_id"
    t.index ["order_id"], name: "index_delivery_requests_on_order_id"
    t.index ["return_request_id"], name: "index_delivery_requests_on_return_request_id"
    t.index ["status"], name: "index_delivery_requests_on_status"
    t.index ["vehicle_id"], name: "index_delivery_requests_on_vehicle_id"
  end

  create_table "drivers", force: :cascade do |t|
    t.string "address"
    t.datetime "created_at", null: false
    t.decimal "current_lat", precision: 10, scale: 6
    t.decimal "current_lng", precision: 10, scale: 6
    t.string "license_number"
    t.datetime "location_updated_at", precision: nil
    t.bigint "logistics_partner_id", null: false
    t.string "name", null: false
    t.string "phone", null: false
    t.string "status", default: "offline"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id"
    t.index ["logistics_partner_id"], name: "index_drivers_on_logistics_partner_id"
    t.index ["vehicle_id"], name: "index_drivers_on_vehicle_id"
  end

  create_table "financial_ledgers", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.string "credit_account"
    t.string "debit_account"
    t.string "description"
    t.bigint "ledgerable_id", null: false
    t.string "ledgerable_type", null: false
    t.string "transaction_type"
    t.datetime "updated_at", null: false
    t.index ["credit_account"], name: "index_financial_ledgers_on_credit_account"
    t.index ["debit_account"], name: "index_financial_ledgers_on_debit_account"
    t.index ["ledgerable_type", "ledgerable_id"], name: "index_financial_ledgers_on_ledgerable"
  end

  create_table "hero_banners", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "display_order"
    t.datetime "end_date"
    t.boolean "is_active"
    t.string "link"
    t.datetime "start_date"
    t.string "subtitle"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "legal_pages", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.boolean "published", default: false
    t.datetime "published_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["key"], name: "index_legal_pages_on_key", unique: true
  end

  create_table "line_items", force: :cascade do |t|
    t.decimal "commission_amount", precision: 10, scale: 2
    t.decimal "commission_rate", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.integer "package_id"
    t.decimal "price", precision: 10, scale: 2, null: false
    t.bigint "product_id", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.jsonb "variant_attributes", default: {}
    t.index ["order_id"], name: "index_line_items_on_order_id"
    t.index ["product_id", "order_id"], name: "index_line_items_on_product_id_and_order_id"
    t.index ["product_id"], name: "index_line_items_on_product_id"
    t.index ["variant_attributes"], name: "index_line_items_on_variant_attributes", using: :gin
  end

  create_table "logistics_partners", force: :cascade do |t|
    t.string "account_number"
    t.boolean "active", default: true
    t.string "address"
    t.string "api_endpoint"
    t.string "api_key"
    t.string "bank_name"
    t.decimal "base_rate", precision: 10, scale: 2, default: "0.0"
    t.string "business_license"
    t.decimal "commission_rate", precision: 5, scale: 2, default: "0.0"
    t.string "contact_person"
    t.string "coverage_zones", default: [], array: true
    t.datetime "created_at", null: false
    t.integer "delivery_speed", default: 0
    t.string "description"
    t.integer "dispatch_mode", default: 0, null: false
    t.integer "estimated_days", default: 1
    t.string "insurance_info"
    t.decimal "min_charge", precision: 10, scale: 2, default: "0.0"
    t.string "name", null: false
    t.boolean "online", default: false
    t.string "operating_region"
    t.decimal "per_km_rate", precision: 10, scale: 2, default: "0.0"
    t.string "phone"
    t.boolean "remittance_required", default: false
    t.decimal "return_fee", precision: 10, scale: 2, default: "0.0"
    t.integer "status", default: 0
    t.jsonb "supported_vehicles", default: []
    t.string "telebirr_number"
    t.string "tin"
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_logistics_partners_on_status"
  end

  create_table "manual_dispatches", force: :cascade do |t|
    t.bigint "admin_user_id"
    t.datetime "created_at", null: false
    t.bigint "delivery_request_id", null: false
    t.bigint "logistics_partner_id"
    t.text "notes"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_manual_dispatches_on_admin_user_id"
    t.index ["delivery_request_id"], name: "index_manual_dispatches_on_delivery_request_id"
    t.index ["logistics_partner_id"], name: "index_manual_dispatches_on_logistics_partner_id"
  end

  create_table "membership_plans", force: :cascade do |t|
    t.boolean "active", default: true
    t.boolean "analytics_access", default: false
    t.string "badge_text"
    t.decimal "commission_rate", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_days"
    t.integer "featured_duration_days"
    t.boolean "featured_included", default: false
    t.jsonb "features"
    t.string "name", null: false
    t.decimal "price", precision: 10, scale: 2, default: "0.0"
    t.boolean "priority_support", default: false
    t.integer "sponsored_product_limit", default: 0
    t.datetime "updated_at", null: false
    t.decimal "yearly_price", precision: 10, scale: 2
  end

  create_table "messages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.bigint "receiver_id", null: false
    t.bigint "sender_id", null: false
    t.datetime "updated_at", null: false
    t.index ["receiver_id"], name: "index_messages_on_receiver_id"
    t.index ["sender_id"], name: "index_messages_on_sender_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "email_status", default: "pending"
    t.jsonb "metadata"
    t.integer "notification_type"
    t.datetime "push_sent_at"
    t.string "push_status", default: "pending"
    t.boolean "read"
    t.string "sms_status", default: "pending"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["notification_type"], name: "index_notifications_on_notification_type"
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id", "read"], name: "index_notifications_on_user_id_and_read"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "order_events", force: :cascade do |t|
    t.bigint "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.bigint "order_id", null: false
    t.string "status_from"
    t.string "status_to"
    t.datetime "updated_at", null: false
    t.index ["actor_type", "actor_id"], name: "index_order_events_on_actor"
    t.index ["event_type"], name: "index_order_events_on_event_type"
    t.index ["order_id"], name: "index_order_events_on_order_id"
  end

  create_table "order_payouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.bigint "payout_id", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id", "payout_id"], name: "index_order_payouts_on_order_id_and_payout_id", unique: true
    t.index ["order_id"], name: "index_order_payouts_on_order_id"
    t.index ["payout_id"], name: "index_order_payouts_on_payout_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "acceptance_deadline"
    t.datetime "accepted_at"
    t.string "checkout_group_id", limit: 36
    t.boolean "cod_reconciled", default: false, null: false
    t.decimal "commission_amount", precision: 10, scale: 2, default: "0.0"
    t.decimal "commission_rate", precision: 5, scale: 2
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "delivery_pin"
    t.decimal "discount_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.string "idempotency_key"
    t.string "invoice_token"
    t.integer "lock_version", default: 0, null: false
    t.datetime "paid_at"
    t.string "payment_method"
    t.integer "payment_method_enum", default: 0
    t.integer "payment_status", default: 0
    t.string "payment_transaction_id"
    t.string "pickup_pin"
    t.string "public_invoice_token"
    t.decimal "refunded_amount", precision: 10, scale: 2, default: "0.0"
    t.datetime "rejected_at"
    t.decimal "restocking_fee_percent", precision: 5, scale: 2, default: "0.0"
    t.string "return_shipping_responsibility", default: "buyer"
    t.integer "return_window_days", default: 7
    t.decimal "seller_earning", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "service_fee", precision: 10, scale: 2, default: "0.0"
    t.datetime "shipped_at"
    t.text "shipping_address", null: false
    t.decimal "shipping_cost", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "status", default: 0
    t.decimal "total", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.decimal "vat_amount", precision: 10, scale: 2, default: "0.0"
    t.bigint "vendor_id", null: false
    t.index ["checkout_group_id"], name: "index_orders_on_checkout_group_id"
    t.index ["created_at"], name: "index_orders_on_created_at"
    t.index ["idempotency_key"], name: "index_orders_on_idempotency_key", unique: true
    t.index ["public_invoice_token"], name: "index_orders_on_public_invoice_token"
    t.index ["user_id"], name: "index_orders_on_user_id"
    t.index ["vendor_id"], name: "index_orders_on_vendor_id"
  end

  create_table "otp_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "phone", null: false
    t.boolean "success"
    t.datetime "updated_at", null: false
    t.index ["phone", "created_at"], name: "index_otp_logs_on_phone_and_created_at"
  end

  create_table "package_categories", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.bigint "package_id", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_package_categories_on_category_id"
    t.index ["package_id", "category_id"], name: "index_package_categories_on_package_id_and_category_id", unique: true
    t.index ["package_id"], name: "index_package_categories_on_package_id"
  end

  create_table "package_products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "package_id", null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.jsonb "variant_attributes"
    t.index ["package_id", "product_id"], name: "index_package_products_on_package_id_and_product_id", unique: true
    t.index ["package_id"], name: "index_package_products_on_package_id"
    t.index ["product_id"], name: "index_package_products_on_product_id"
  end

  create_table "packages", force: :cascade do |t|
    t.boolean "bulk_enabled"
    t.datetime "created_at", null: false
    t.text "description"
    t.date "discount_end"
    t.date "discount_start"
    t.string "discount_type"
    t.decimal "discount_value"
    t.boolean "featured", default: false
    t.jsonb "features"
    t.boolean "free_shipping"
    t.text "long_description"
    t.string "name", null: false
    t.decimal "original_price"
    t.decimal "price", precision: 10, scale: 2, null: false
    t.virtual "search_vector", type: :tsvector, as: "to_tsvector('english'::regconfig, (((COALESCE(name, ''::character varying))::text || ' '::text) || COALESCE(description, ''::text)))", stored: true
    t.boolean "seller_pays_shipping", default: false
    t.decimal "shipping_cost"
    t.string "shipping_subsidy_type"
    t.decimal "shipping_subsidy_value", precision: 10, scale: 2
    t.integer "shipping_type"
    t.decimal "shipping_value", precision: 10, scale: 2
    t.integer "status", default: 0
    t.integer "stock"
    t.integer "stock_reserved", default: 0, null: false
    t.float "trending_score", default: 0.0, null: false
    t.datetime "updated_at", null: false
    t.jsonb "variants_data"
    t.bigint "vendor_id", null: false
    t.index ["search_vector"], name: "index_packages_on_search_vector", using: :gin
    t.index ["stock_reserved"], name: "index_packages_on_stock_reserved"
    t.index ["trending_score"], name: "index_packages_on_trending_score"
    t.index ["vendor_id"], name: "index_packages_on_vendor_id"
  end

  create_table "partner_payouts", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.bigint "delivery_request_id", null: false
    t.bigint "logistics_partner_id", null: false
    t.datetime "paid_at"
    t.date "period_end"
    t.date "period_start"
    t.integer "status"
    t.datetime "updated_at", null: false
    t.index ["delivery_request_id"], name: "index_partner_payouts_on_delivery_request_id"
    t.index ["logistics_partner_id"], name: "index_partner_payouts_on_logistics_partner_id"
  end

  create_table "payment_gateways", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "api_endpoint"
    t.string "api_key"
    t.jsonb "config", default: {}
    t.datetime "created_at", null: false
    t.jsonb "credentials_json", default: {}
    t.string "merchant_id"
    t.string "name", null: false
    t.string "provider", null: false
    t.boolean "supports_refunds", default: false
    t.datetime "updated_at", null: false
    t.string "webhook_secret"
    t.index ["provider"], name: "index_payment_gateways_on_provider", unique: true
  end

  create_table "payment_logs", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "idempotency_key"
    t.bigint "membership_plan_id"
    t.bigint "order_id"
    t.string "payment_method"
    t.string "status", default: "pending"
    t.string "transaction_id"
    t.datetime "updated_at", null: false
    t.bigint "vendor_id"
    t.index ["idempotency_key"], name: "index_payment_logs_on_idempotency_key", unique: true
    t.index ["membership_plan_id"], name: "index_payment_logs_on_membership_plan_id"
    t.index ["order_id"], name: "index_payment_logs_on_order_id"
    t.index ["vendor_id"], name: "index_payment_logs_on_vendor_id"
  end

  create_table "payouts", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.string "gateway_reference"
    t.decimal "gross_amount", precision: 10, scale: 2, default: "0.0"
    t.boolean "held", default: false
    t.string "payout_method"
    t.date "period_end"
    t.date "period_start"
    t.datetime "processed_at"
    t.jsonb "recipient_details", default: {}
    t.integer "status", default: 0
    t.decimal "tax_withheld", precision: 10, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.bigint "vendor_id", null: false
    t.index ["vendor_id"], name: "index_payouts_on_vendor_id"
  end

  create_table "price_alerts", force: :cascade do |t|
    t.boolean "alert_sent"
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.decimal "target_price"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["product_id"], name: "index_price_alerts_on_product_id"
    t.index ["user_id"], name: "index_price_alerts_on_user_id"
  end

  create_table "product_attribute_values", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_attribute_id", null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["product_attribute_id"], name: "index_product_attribute_values_on_product_attribute_id"
    t.index ["product_id"], name: "index_product_attribute_values_on_product_id"
  end

  create_table "product_attributes", force: :cascade do |t|
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_product_attributes_on_category_id"
  end

  create_table "product_variants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "fragile", default: false
    t.decimal "height_cm", precision: 10, scale: 2
    t.decimal "length_cm", precision: 10, scale: 2
    t.integer "lock_version", default: 0, null: false
    t.integer "minimum_bulk_quantity"
    t.decimal "price", precision: 10, scale: 2, null: false
    t.bigint "product_id", null: false
    t.boolean "refrigerated", default: false
    t.integer "reserved", default: 0, null: false
    t.string "sku"
    t.integer "stock", default: 0
    t.boolean "unlimited_stock"
    t.datetime "updated_at", null: false
    t.jsonb "variant_attributes", default: {}
    t.decimal "weight_kg", precision: 10, scale: 2
    t.decimal "width_cm", precision: 10, scale: 2
    t.index ["product_id", "stock"], name: "idx_variants_on_product_stock"
    t.index ["product_id"], name: "index_product_variants_on_product_id"
    t.index ["sku"], name: "index_product_variants_on_sku", unique: true, where: "(sku IS NOT NULL)"
    t.index ["variant_attributes"], name: "index_product_variants_on_variant_attributes", using: :gin
  end

  create_table "products", force: :cascade do |t|
    t.boolean "bulk_enabled", default: false, null: false
    t.bigint "category_id", null: false
    t.decimal "commission_rate", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "discount", default: 0
    t.string "discount_type"
    t.decimal "discount_value"
    t.boolean "featured", default: false
    t.decimal "featured_fee", precision: 10, scale: 2
    t.datetime "featured_until"
    t.datetime "flash_sale_ends_at"
    t.decimal "flash_sale_price"
    t.boolean "free_shipping", default: false
    t.decimal "height_cm", precision: 6, scale: 1
    t.boolean "is_flash_sale"
    t.boolean "is_hot_deal", default: false
    t.boolean "is_super_deal"
    t.boolean "is_trending", default: false
    t.decimal "length_cm", precision: 6, scale: 1
    t.integer "max_quantity_per_day"
    t.string "min_order", default: "1 piece"
    t.integer "minimum_bulk_quantity", default: 1, null: false
    t.decimal "original_price", precision: 10, scale: 2
    t.decimal "price", precision: 10, scale: 2
    t.jsonb "product_attributes", default: {}
    t.decimal "rating", precision: 2, scale: 1, default: "0.0"
    t.integer "reviews_count", default: 0
    t.virtual "search_vector", type: :tsvector, as: "to_tsvector('english'::regconfig, (((((COALESCE(title, ''::character varying))::text || ' '::text) || COALESCE(description, ''::text)) || ' '::text) || COALESCE((product_attributes)::text, ''::text)))", stored: true
    t.boolean "seller_pays_shipping", default: false
    t.string "shipping_subsidy_type"
    t.decimal "shipping_subsidy_value", precision: 10, scale: 2
    t.integer "sold_count"
    t.boolean "sponsored", default: false, null: false
    t.integer "status", default: 0
    t.integer "stock", default: 0
    t.integer "stock_reserved", default: 0, null: false
    t.datetime "super_deal_ends_at"
    t.decimal "super_deal_price"
    t.string "title", null: false
    t.float "trending_score", default: 0.0, null: false
    t.datetime "updated_at", null: false
    t.jsonb "variants_data"
    t.bigint "vendor_id", null: false
    t.integer "views", default: 0
    t.integer "views_count"
    t.decimal "weight_kg", precision: 8, scale: 3
    t.decimal "width_cm", precision: 6, scale: 1
    t.index ["category_id"], name: "index_products_on_category_id"
    t.index ["free_shipping"], name: "index_products_on_free_shipping"
    t.index ["is_trending"], name: "index_products_on_is_trending"
    t.index ["product_attributes"], name: "index_products_on_product_attributes", using: :gin
    t.index ["rating"], name: "index_products_on_rating"
    t.index ["search_vector"], name: "index_products_on_search_vector", using: :gin
    t.index ["seller_pays_shipping", "shipping_subsidy_type", "shipping_subsidy_value"], name: "idx_products_delivery_fields"
    t.index ["seller_pays_shipping"], name: "index_products_on_seller_pays_shipping"
    t.index ["sponsored"], name: "index_products_on_sponsored", where: "(sponsored = true)"
    t.index ["trending_score"], name: "index_products_on_trending_score"
    t.index ["vendor_id"], name: "index_products_on_vendor_id"
  end

  create_table "promotional_section_products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.bigint "promotional_section_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_promotional_section_products_on_product_id"
    t.index ["promotional_section_id", "product_id"], name: "idx_on_promotional_section_id_product_id_8d8f298d6a", unique: true
    t.index ["promotional_section_id"], name: "index_promotional_section_products_on_promotional_section_id"
  end

  create_table "promotional_sections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "display_order"
    t.boolean "is_active", default: true
    t.integer "max_products", default: 30
    t.string "name", null: false
    t.string "section_type"
    t.string "slug", null: false
    t.boolean "system_generated", default: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_promotional_sections_on_slug", unique: true
  end

  create_table "questions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.text "question"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["product_id"], name: "index_questions_on_product_id"
    t.index ["user_id"], name: "index_questions_on_user_id"
  end

  create_table "rate_cards", force: :cascade do |t|
    t.decimal "base_rate", precision: 10, scale: 2, default: "50.0"
    t.datetime "created_at", null: false
    t.decimal "express_surcharge_percent", precision: 5, scale: 2, default: "30.0"
    t.decimal "fragile_surcharge", precision: 10, scale: 2, default: "50.0"
    t.bigint "logistics_partner_id", null: false
    t.decimal "min_charge", precision: 10, scale: 2, default: "100.0"
    t.decimal "per_km_rate", precision: 10, scale: 2, default: "15.0"
    t.datetime "updated_at", null: false
    t.string "vehicle_type", null: false
    t.decimal "weight_surcharge_per_kg_above_5kg", precision: 10, scale: 2, default: "2.0"
    t.index ["logistics_partner_id", "vehicle_type"], name: "index_rate_cards_on_logistics_partner_id_and_vehicle_type", unique: true
    t.index ["logistics_partner_id"], name: "index_rate_cards_on_logistics_partner_id"
  end

  create_table "recently_vieweds", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.datetime "viewed_at"
    t.index ["product_id"], name: "index_recently_vieweds_on_product_id"
    t.index ["user_id"], name: "index_recently_vieweds_on_user_id"
  end

  create_table "regions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_regions_on_name", unique: true
  end

  create_table "reports", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.string "reason", null: false
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["product_id"], name: "index_reports_on_product_id"
    t.index ["user_id"], name: "index_reports_on_user_id"
  end

  create_table "reservations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "order_id"
    t.bigint "product_id", null: false
    t.integer "product_variant_id"
    t.integer "quantity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_reservations_on_expires_at"
    t.index ["order_id"], name: "index_reservations_on_order_id"
    t.index ["product_id", "user_id"], name: "index_active_reservations_on_product_user", unique: true, where: "(order_id IS NULL)"
    t.index ["product_id"], name: "index_reservations_on_product_id"
    t.index ["product_variant_id"], name: "index_reservations_on_product_variant_id"
    t.index ["user_id"], name: "index_reservations_on_user_id"
  end

  create_table "return_policies", force: :cascade do |t|
    t.jsonb "applicable_categories", default: []
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "excluded_categories", default: []
    t.boolean "is_active", default: true
    t.string "name", null: false
    t.decimal "restocking_fee_percent", precision: 5, scale: 2, default: "0.0"
    t.string "return_shipping_responsibility", default: "buyer"
    t.integer "return_window_days", default: 7, null: false
    t.datetime "updated_at", null: false
  end

  create_table "return_requests", force: :cascade do |t|
    t.text "admin_notes"
    t.datetime "created_at", null: false
    t.text "details"
    t.string "liability", default: "buyer"
    t.bigint "order_id", null: false
    t.string "reason"
    t.datetime "received_at"
    t.decimal "return_shipping_cost", precision: 10, scale: 2
    t.string "return_tracking_number"
    t.integer "status"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["order_id"], name: "index_return_requests_on_order_id"
    t.index ["user_id"], name: "index_return_requests_on_user_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.bigint "product_id"
    t.integer "rating"
    t.integer "reviewable_id"
    t.string "reviewable_type"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "vendor_id"
    t.index ["product_id"], name: "index_reviews_on_product_id"
    t.index ["reviewable_type", "reviewable_id"], name: "index_reviews_on_reviewable_type_and_reviewable_id"
    t.index ["user_id"], name: "index_reviews_on_user_id"
  end

  create_table "saved_searches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "query"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_saved_searches_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
  end

  create_table "shipping_rates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "express_days"
    t.decimal "express_rate", precision: 10, scale: 2, default: "0.0"
    t.bigint "region_id", null: false
    t.integer "standard_days"
    t.decimal "standard_rate", precision: 10, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.bigint "woreda_id"
    t.bigint "zone_id"
    t.index ["region_id", "zone_id", "woreda_id"], name: "index_shipping_rates_on_region_zone_woreda", unique: true
    t.index ["region_id"], name: "index_shipping_rates_on_region_id"
    t.index ["woreda_id"], name: "index_shipping_rates_on_woreda_id"
    t.index ["zone_id"], name: "index_shipping_rates_on_zone_id"
  end

  create_table "sms_logs", force: :cascade do |t|
    t.integer "attempt"
    t.datetime "created_at", null: false
    t.text "message"
    t.string "phone"
    t.text "response"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  create_table "sms_providers", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "api_key"
    t.string "auth_token"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "phone_number"
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["provider"], name: "index_sms_providers_on_provider", unique: true
  end

  create_table "translations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "source_text", null: false
    t.string "target_locale", null: false
    t.text "translated_text", null: false
    t.datetime "updated_at", null: false
    t.index ["source_text", "target_locale"], name: "index_translations_on_source_text_and_target_locale", unique: true
  end

  create_table "user_consents", force: :cascade do |t|
    t.datetime "accepted_at", null: false
    t.string "agreement_type", null: false
    t.integer "agreement_version", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "agreement_type"], name: "index_user_consents_on_user_id_and_agreement_type", unique: true
    t.index ["user_id"], name: "index_user_consents_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "company_name"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "email_address_old"
    t.boolean "email_notifications", default: true, null: false
    t.integer "failed_attempts", default: 0
    t.string "fayda_id"
    t.string "fcm_token"
    t.string "full_name"
    t.datetime "last_sign_in_at"
    t.datetime "locked_until"
    t.bigint "logistics_partner_id"
    t.string "national_id"
    t.string "otp_code"
    t.datetime "otp_expires_at"
    t.string "password_digest", null: false
    t.jsonb "permissions"
    t.string "phone"
    t.boolean "phone_verified", default: false
    t.boolean "promotional_emails", default: false, null: false
    t.boolean "push_notifications", default: true, null: false
    t.string "refresh_token_digest"
    t.integer "role_mask"
    t.string "shop_location"
    t.string "shop_name"
    t.boolean "sms_notifications", default: true, null: false
    t.integer "status", default: 0, null: false
    t.string "tax_id"
    t.string "tin"
    t.datetime "updated_at", null: false
    t.boolean "verified"
    t.datetime "welcomed_at"
    t.index ["email_address_old"], name: "index_users_on_email_address_old", unique: true
    t.index ["logistics_partner_id"], name: "index_users_on_logistics_partner_id"
    t.index ["phone"], name: "index_users_on_phone", unique: true
  end

  create_table "vehicles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "driver_name"
    t.string "driver_phone"
    t.boolean "fragile_capable", default: false
    t.decimal "height_cm", precision: 7, scale: 2
    t.decimal "length_cm", precision: 7, scale: 2
    t.bigint "logistics_partner_id", null: false
    t.decimal "max_volume_cm3", precision: 12, scale: 2
    t.decimal "max_weight_kg", precision: 8, scale: 2
    t.string "plate_number"
    t.boolean "refrigerated", default: false
    t.string "status", default: "available"
    t.datetime "updated_at", null: false
    t.string "vehicle_type", null: false
    t.decimal "width_cm", precision: 7, scale: 2
    t.index ["logistics_partner_id"], name: "index_vehicles_on_logistics_partner_id"
  end

  create_table "vendors", force: :cascade do |t|
    t.boolean "accepting_orders"
    t.string "account_name"
    t.string "account_number"
    t.datetime "approved_at"
    t.integer "average_processing_hours"
    t.float "avg_response_time_hours"
    t.string "bank_account_number"
    t.string "bank_name"
    t.text "business_address"
    t.decimal "business_lat", precision: 10, scale: 6
    t.string "business_license"
    t.decimal "business_lng", precision: 10, scale: 6
    t.string "business_name"
    t.decimal "commission_rate", precision: 5, scale: 2
    t.string "country", default: "ET"
    t.datetime "created_at", null: false
    t.integer "declined_orders_count"
    t.text "description"
    t.boolean "featured"
    t.datetime "featured_until"
    t.string "id_document"
    t.boolean "is_bulk_supplier", default: false, null: false
    t.boolean "is_open", default: true, null: false
    t.datetime "last_login_at"
    t.text "long_description"
    t.datetime "membership_expires_at"
    t.boolean "membership_paid", default: false
    t.integer "membership_plan_id"
    t.string "national_id"
    t.integer "payout_method", default: 0
    t.string "phone"
    t.boolean "pickup_ready", default: false
    t.datetime "pickup_ready_deadline"
    t.boolean "premium", default: false
    t.datetime "premium_expires_at"
    t.datetime "premium_since"
    t.integer "preparation_time_minutes", default: 60
    t.boolean "pro", default: false
    t.integer "products_count", default: 0, null: false
    t.decimal "rating", precision: 2, scale: 1, default: "0.0"
    t.datetime "rejected_at"
    t.text "rejection_reason"
    t.datetime "reopen_at"
    t.integer "reorder_rate", default: 0
    t.integer "reviews_count", default: 0
    t.integer "sponsored_products_count", default: 0
    t.integer "status", default: 0
    t.text "suspension_reason"
    t.string "telebirr_account"
    t.string "telebirr_number"
    t.string "tin"
    t.integer "total_orders_count"
    t.integer "total_sales_count_cache", default: 0, null: false
    t.integer "unanswered_orders_count"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "verified", default: false
    t.integer "years_in_business", default: 1
    t.index ["is_bulk_supplier"], name: "index_vendors_on_is_bulk_supplier"
    t.index ["membership_plan_id"], name: "index_vendors_on_membership_plan_id"
    t.index ["national_id"], name: "index_vendors_on_national_id", unique: true
    t.index ["user_id"], name: "index_vendors_on_user_id"
  end

  create_table "wishlist_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "wishlist_id", null: false
    t.index ["product_id"], name: "index_wishlist_items_on_product_id"
    t.index ["wishlist_id", "product_id"], name: "index_wishlist_items_on_wishlist_id_and_product_id", unique: true
    t.index ["wishlist_id"], name: "index_wishlist_items_on_wishlist_id"
  end

  create_table "wishlists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_wishlists_on_user_id"
  end

  create_table "woredas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "latitude"
    t.decimal "longitude"
    t.decimal "max_lat"
    t.decimal "max_lng"
    t.decimal "min_lat"
    t.decimal "min_lng"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "zone_id", null: false
    t.index ["zone_id", "name"], name: "index_woredas_on_zone_id_and_name", unique: true
    t.index ["zone_id"], name: "index_woredas_on_zone_id"
  end

  create_table "zones", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "region_id", null: false
    t.datetime "updated_at", null: false
    t.index ["region_id", "name"], name: "index_zones_on_region_id_and_name", unique: true
    t.index ["region_id"], name: "index_zones_on_region_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "addresses", "regions"
  add_foreign_key "addresses", "users"
  add_foreign_key "addresses", "woredas"
  add_foreign_key "addresses", "zones"
  add_foreign_key "admin_audit_logs", "users", column: "admin_user_id"
  add_foreign_key "answers", "questions"
  add_foreign_key "answers", "users"
  add_foreign_key "bulk_order_items", "bulk_orders"
  add_foreign_key "bulk_order_items", "products"
  add_foreign_key "bulk_orders", "users"
  add_foreign_key "cart_items", "carts"
  add_foreign_key "cart_items", "products"
  add_foreign_key "carts", "users"
  add_foreign_key "checkout_groups", "users"
  add_foreign_key "collections_products", "collections"
  add_foreign_key "collections_products", "products"
  add_foreign_key "comparisons", "products"
  add_foreign_key "comparisons", "users"
  add_foreign_key "delivery_requests", "checkout_groups"
  add_foreign_key "delivery_requests", "logistics_partners"
  add_foreign_key "delivery_requests", "orders"
  add_foreign_key "delivery_requests", "return_requests"
  add_foreign_key "delivery_requests", "vehicles"
  add_foreign_key "drivers", "logistics_partners"
  add_foreign_key "drivers", "vehicles"
  add_foreign_key "line_items", "orders"
  add_foreign_key "line_items", "products"
  add_foreign_key "manual_dispatches", "delivery_requests"
  add_foreign_key "manual_dispatches", "logistics_partners"
  add_foreign_key "manual_dispatches", "users", column: "admin_user_id"
  add_foreign_key "messages", "users", column: "receiver_id"
  add_foreign_key "messages", "users", column: "sender_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "order_events", "orders"
  add_foreign_key "order_payouts", "orders"
  add_foreign_key "order_payouts", "payouts"
  add_foreign_key "orders", "users"
  add_foreign_key "orders", "vendors"
  add_foreign_key "package_categories", "categories"
  add_foreign_key "package_categories", "packages"
  add_foreign_key "package_products", "packages"
  add_foreign_key "package_products", "products"
  add_foreign_key "packages", "vendors"
  add_foreign_key "partner_payouts", "delivery_requests"
  add_foreign_key "partner_payouts", "logistics_partners"
  add_foreign_key "payment_logs", "orders"
  add_foreign_key "payouts", "vendors"
  add_foreign_key "price_alerts", "products"
  add_foreign_key "price_alerts", "users"
  add_foreign_key "product_attribute_values", "product_attributes"
  add_foreign_key "product_attribute_values", "products"
  add_foreign_key "product_attributes", "categories"
  add_foreign_key "product_variants", "products"
  add_foreign_key "products", "categories"
  add_foreign_key "products", "vendors"
  add_foreign_key "promotional_section_products", "products"
  add_foreign_key "promotional_section_products", "promotional_sections"
  add_foreign_key "questions", "products"
  add_foreign_key "questions", "users"
  add_foreign_key "rate_cards", "logistics_partners"
  add_foreign_key "recently_vieweds", "products"
  add_foreign_key "recently_vieweds", "users"
  add_foreign_key "reports", "products"
  add_foreign_key "reports", "users"
  add_foreign_key "reservations", "orders"
  add_foreign_key "reservations", "products"
  add_foreign_key "reservations", "users"
  add_foreign_key "return_requests", "orders"
  add_foreign_key "return_requests", "users"
  add_foreign_key "reviews", "products"
  add_foreign_key "reviews", "users"
  add_foreign_key "saved_searches", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "shipping_rates", "regions"
  add_foreign_key "shipping_rates", "woredas"
  add_foreign_key "shipping_rates", "zones"
  add_foreign_key "user_consents", "users"
  add_foreign_key "users", "logistics_partners"
  add_foreign_key "vehicles", "logistics_partners"
  add_foreign_key "vendors", "membership_plans"
  add_foreign_key "vendors", "users"
  add_foreign_key "wishlist_items", "products"
  add_foreign_key "wishlist_items", "wishlists"
  add_foreign_key "wishlists", "users"
  add_foreign_key "woredas", "zones"
  add_foreign_key "zones", "regions"
end
