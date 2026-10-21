class AddDescriptionEtcToPackages < ActiveRecord::Migration[8.1]
  def change
    # description column already exists, so we skip it
    add_column :packages, :long_description, :text
    add_column :packages, :discount_type, :string
    add_column :packages, :discount_value, :decimal
    add_column :packages, :discount_start, :date
    add_column :packages, :discount_end, :date
    add_column :packages, :original_price, :decimal
  end
end
