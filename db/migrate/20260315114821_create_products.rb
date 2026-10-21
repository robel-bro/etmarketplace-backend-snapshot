class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :title, null: false
      t.text :description
      t.decimal :price, precision: 10, scale: 2, null: false
      t.integer :stock, default: 0
      t.references :vendor, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.integer :status, default: 0  # 0 = draft, 1 = active, 2 = archived

      t.timestamps
    end
  end
end
