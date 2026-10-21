class CreateAttributeValues < ActiveRecord::Migration[8.1]
  def change
    create_table :attribute_values do |t|
      t.integer :attribute_id
      t.string :value
      t.string :display_value

      t.timestamps
    end
  end
end
