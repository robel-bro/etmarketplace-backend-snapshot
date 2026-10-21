# db/migrate/20260730_add_geocoding_fields_to_addresses.rb
class AddGeocodingFieldsToAddresses < ActiveRecord::Migration[8.1]
  def change
    add_column :addresses, :city, :string
    add_column :addresses, :woreda_text, :string   # textual woreda (e.g., "Woreda 03")
    add_column :addresses, :street, :string
    add_column :addresses, :source, :string        # "auto" or "manual"

    # Optional: index for source filtering (manual reviews)
    add_index :addresses, :source, where: "source = 'manual'"
  end
end