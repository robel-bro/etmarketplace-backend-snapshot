class CreateZones < ActiveRecord::Migration[8.1]
  def change
    create_table :zones do |t|
      t.string :name, null: false
      t.references :region, null: false, foreign_key: true
      t.timestamps
    end
    add_index :zones, [:region_id, :name], unique: true
  end
end
