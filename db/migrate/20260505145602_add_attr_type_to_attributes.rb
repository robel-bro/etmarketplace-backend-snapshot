class AddAttrTypeToAttributes < ActiveRecord::Migration[8.1]
  def change
    add_column :attributes, :attr_type, :integer
  end
end
