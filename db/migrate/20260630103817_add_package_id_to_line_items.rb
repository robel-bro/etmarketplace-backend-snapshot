class AddPackageIdToLineItems < ActiveRecord::Migration[8.1]
  def change
    add_column :line_items, :package_id, :integer
  end
end
