class MakeProductIdNullableInReviews < ActiveRecord::Migration[8.1]
  def change
    change_column_null :reviews, :product_id, true
  end
end
