class CreateHeroBanners < ActiveRecord::Migration[8.1]
  def change
    create_table :hero_banners do |t|
      t.string :title
      t.string :subtitle
      t.string :link
      t.datetime :start_date
      t.datetime :end_date
      t.integer :display_order
      t.boolean :is_active

      t.timestamps
    end
  end
end
