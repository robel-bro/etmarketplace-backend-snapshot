class WishlistItem < ApplicationRecord
  belongs_to :wishlist
  belongs_to :product

  validates :product_id, uniqueness: { scope: :wishlist_id }
end