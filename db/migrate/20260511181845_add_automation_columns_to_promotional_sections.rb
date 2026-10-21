class AddAutomationColumnsToPromotionalSections < ActiveRecord::Migration[8.1]
  def change
    add_column :promotional_sections, :max_products, :integer, default: 30
    add_column :promotional_sections, :system_generated, :boolean, default: false
  end
end
