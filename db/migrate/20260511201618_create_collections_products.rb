class CreateCollectionsProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :collections_products do |t|
      t.references :collection, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true

      t.timestamps
    end
  end
end
