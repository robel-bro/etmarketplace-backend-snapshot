class AddSponsoredToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :sponsored, :boolean, default: false, null: false
    add_index :products, :sponsored, where: "sponsored = true"
  end
end