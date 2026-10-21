class AddLinkToAdminAnnouncements < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_announcements, :link, :string
  end
end
