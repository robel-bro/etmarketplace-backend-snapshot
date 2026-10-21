class AddProductVariantIdToReservations < ActiveRecord::Migration[8.1]
  def change
    add_column :reservations, :product_variant_id, :integer
    add_index :reservations, :product_variant_id
    # Optional foreign key if you want referential integrity:
    # add_foreign_key :reservations, :product_variants, column: :product_variant_id
  end
end