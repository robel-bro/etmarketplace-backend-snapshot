class CreateAdminAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_announcements do |t|
      t.string :title
      t.text :content
      t.string :announcement_type
      t.string :image
      t.boolean :active
      t.date :start_date
      t.date :end_date

      t.timestamps
    end
  end
end
