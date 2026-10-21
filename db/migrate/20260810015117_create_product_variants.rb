class CreateProductVariants < ActiveRecord::Migration[8.1]
  def up
    create_table :product_variants do |t|
      t.references :product, null: false, foreign_key: true
      t.string :sku
      t.decimal :price, precision: 10, scale: 2, null: false
      t.integer :stock, default: 0, null: false
      t.integer :reserved, default: 0, null: false
      t.jsonb :attributes, default: {}
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end

    add_index :product_variants, :sku, unique: true, where: "sku IS NOT NULL"
    add_index :product_variants, [:product_id, :stock], name: 'idx_variants_on_product_stock'
    add_index :product_variants, :attributes, using: :gin

    # ── Data migration – raw SQL to avoid model dependency ──
    say_with_time "Migrating existing variant data from products.variants_data" do
      products_with_variants = execute <<-SQL
        SELECT id, variants_data FROM products WHERE variants_data IS NOT NULL AND variants_data != '[]'::jsonb
      SQL

      products_with_variants.each do |row|
        product_id = row['id']
        variants = JSON.parse(row['variants_data'] || '[]')
        next if variants.blank?

        variants.each do |v|
          attrs = v['attributes'] || {}
          price  = v['price'].to_f
          stock  = v['stock'].to_i
          next if price <= 0

          attrs_json = ActiveRecord::Base.connection.quote(attrs.to_json)

          execute <<-SQL
            INSERT INTO product_variants (product_id, price, stock, reserved, attributes, created_at, updated_at)
            VALUES (
              #{product_id},
              #{price},
              #{stock},
              0,
              #{attrs_json}::jsonb,
              NOW(),
              NOW()
            )
          SQL
        end
      end
    end
  end

  def down
    drop_table :product_variants
  end
end