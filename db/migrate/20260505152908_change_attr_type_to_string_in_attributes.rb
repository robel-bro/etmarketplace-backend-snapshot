class ChangeAttrTypeToStringInAttributes < ActiveRecord::Migration[8.1]
  def change
    change_column :attributes, :attr_type, :string
  end
end
