class AddVariantsDataToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :variants_data, :jsonb
  end
end
