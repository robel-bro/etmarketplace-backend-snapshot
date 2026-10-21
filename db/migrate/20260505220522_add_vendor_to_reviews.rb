class AddVendorToReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :reviews, :vendor_id, :integer
    add_column :reviews, :reviewable_type, :string
    add_column :reviews, :reviewable_id, :integer
    add_index :reviews, [:reviewable_type, :reviewable_id]
  end
end
