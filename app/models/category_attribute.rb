class CategoryAttribute < ApplicationRecord
  belongs_to :category
  belongs_to :attr, class_name: 'Attribute', foreign_key: 'attribute_id'
end