# app/models/recently_viewed.rb
class RecentlyViewed < ApplicationRecord
  belongs_to :user
  belongs_to :product

  validates :user_id, uniqueness: { scope: :product_id }

  scope :recent, -> { order(viewed_at: :desc) }
end