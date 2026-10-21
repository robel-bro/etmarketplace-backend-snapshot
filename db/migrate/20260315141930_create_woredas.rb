class CreateWoredas < ActiveRecord::Migration[8.1]
  def change
    create_table :woredas do |t|
      t.string :name, null: false
      t.references :zone, null: false, foreign_key: true
      t.timestamps
    end
    add_index :woredas, [:zone_id, :name], unique: true
  end
end
