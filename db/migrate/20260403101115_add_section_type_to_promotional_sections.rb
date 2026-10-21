class AddSectionTypeToPromotionalSections < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:promotional_sections, :section_type)
      add_column :promotional_sections, :section_type, :string
    end
  end
end
