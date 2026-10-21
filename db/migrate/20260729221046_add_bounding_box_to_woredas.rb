class AddBoundingBoxToWoredas < ActiveRecord::Migration[8.1]
  def change
    add_column :woredas, :min_lat, :decimal
    add_column :woredas, :min_lng, :decimal
    add_column :woredas, :max_lat, :decimal
    add_column :woredas, :max_lng, :decimal
  end
end
