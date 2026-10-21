class AttributeValue < ApplicationRecord
  belongs_to :attr, class_name: 'Attribute', foreign_key: 'attribute_id'
  validates :value, presence: true, uniqueness: { scope: :attribute_id }
end