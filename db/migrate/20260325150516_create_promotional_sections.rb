class CreatePromotionalSections < ActiveRecord::Migration[8.1]
  def change
    create_table :promotional_sections do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :section_type
      t.integer :display_order
      t.boolean :is_active, default: true
      t.timestamps
    end
    add_index :promotional_sections, :slug, unique: true
  end
end
