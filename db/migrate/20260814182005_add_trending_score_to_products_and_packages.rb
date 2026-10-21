class AddTrendingScoreToProductsAndPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :trending_score, :float, default: 0.0, null: false
    add_column :packages, :trending_score, :float, default: 0.0, null: false

    add_index :products, :trending_score
    add_index :packages, :trending_score
  end
end