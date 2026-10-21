class ProductAttribute < ApplicationRecord
  has_many :product_attribute_values, dependent: :destroy
  belongs_to :category, optional: true
  validates :name, presence: true, uniqueness: true
end