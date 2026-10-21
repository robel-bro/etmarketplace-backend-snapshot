class CreatePackages < ActiveRecord::Migration[8.0]
  def change
    create_table :packages do |t|
      t.references :vendor, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.decimal :price, precision: 10, scale: 2, null: false
      t.integer :status, default: 0  # 0: draft, 1: active, 2: archived
      t.boolean :featured, default: false
      t.timestamps
    end
  end
end
