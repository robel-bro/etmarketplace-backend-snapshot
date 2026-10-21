# db/migrate/20260321110152_create_recently_vieweds.rb
class CreateRecentlyVieweds < ActiveRecord::Migration[8.1]
  def change
    create_table :recently_vieweds do |t|
      t.references :user, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.datetime :viewed_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.timestamps
    end

    add_index :recently_vieweds, [:user_id, :product_id], unique: true
    add_index :recently_vieweds, [:user_id, :viewed_at]
  end
end