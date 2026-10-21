class AddVariantAttributesToComparisons < ActiveRecord::Migration[8.1]
  def change
    add_column :comparisons, :variant_attributes, :jsonb
  end
end
