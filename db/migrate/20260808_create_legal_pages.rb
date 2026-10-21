# db/migrate/20260808_create_legal_pages.rb
class CreateLegalPages < ActiveRecord::Migration[8.1]
  def change
    create_table :legal_pages do |t|
      t.string :key, null: false, index: { unique: true }
      t.string :title, null: false
      t.text :body, null: false
      t.integer :version, null: false, default: 1
      t.boolean :published, default: false
      t.datetime :published_at
      t.timestamps
    end
  end
end