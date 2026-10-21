class ProductAttributeValue < ApplicationRecord
  belongs_to :product
  belongs_to :product_attribute
  validates :value, presence: true
end