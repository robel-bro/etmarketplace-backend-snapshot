class Comparison < ApplicationRecord
  belongs_to :user
  belongs_to :product

  validates :user_id, uniqueness: { scope: :product_id }

  attribute :variant_attributes, :json, default: {}
end