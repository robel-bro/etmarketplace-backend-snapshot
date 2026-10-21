class AddProcessingTimeToVendors < ActiveRecord::Migration[8.1]
  def change
    add_column :vendors, :average_processing_hours, :integer
  end
end
