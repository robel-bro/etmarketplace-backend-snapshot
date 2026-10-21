class CreateAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :announcements do |t|
      t.string :title
      t.text :content
      t.boolean :active

      t.timestamps
    end
  end
end
