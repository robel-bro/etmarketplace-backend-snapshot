class CreateCollections < ActiveRecord::Migration[8.0]
  def change
    create_table :collections do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.json :auto_criteria
      t.boolean :is_active, default: true
      t.datetime :start_date
      t.datetime :end_date
      t.integer :display_order
      t.timestamps
    end
    add_index :collections, :slug, unique: true
  end
end
