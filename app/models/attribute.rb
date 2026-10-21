class Attribute < ApplicationRecord
  has_many :attribute_values, dependent: :destroy
  has_many :category_attributes, dependent: :destroy
  has_many :categories, through: :category_attributes

  enum :attr_type, { text: 0, number: 1, dropdown: 2, boolean: 3, visual: 4 }
end