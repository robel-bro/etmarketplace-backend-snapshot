class PriceAlert < ApplicationRecord
  belongs_to :user
  belongs_to :product
  validates :target_price, presence: true, numericality: { greater_than: 0 }
end