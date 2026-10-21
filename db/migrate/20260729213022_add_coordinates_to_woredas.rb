class AddCoordinatesToWoredas < ActiveRecord::Migration[8.1]
  def change
    add_column :woredas, :latitude, :decimal
    add_column :woredas, :longitude, :decimal
  end
end
