class CreateAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :region, null: false, foreign_key: true
      t.references :zone, null: true, foreign_key: true
      t.references :woreda, null: true, foreign_key: true
      t.string :address_line, null: false
      t.string :landmark
      t.boolean :is_default, default: false

      t.timestamps
    end
    add_index :addresses, [:user_id, :is_default]
  end
end
