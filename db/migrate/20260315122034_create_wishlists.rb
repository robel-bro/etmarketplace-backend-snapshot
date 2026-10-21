class CreateWishlists < ActiveRecord::Migration[8.1]
  def change
    create_table :wishlists do |t|
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :wishlists, :user_id, unique: true, if_not_exists: true
  end
end
