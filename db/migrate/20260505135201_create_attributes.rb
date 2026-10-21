class CreateAttributes < ActiveRecord::Migration[8.1]
  def change
    create_table :attributes do |t|
      t.string :name
      t.string :display_name
      t.integer :attribute_type
      t.boolean :is_filterable
      t.boolean :is_variant

      t.timestamps
    end
  end
end
