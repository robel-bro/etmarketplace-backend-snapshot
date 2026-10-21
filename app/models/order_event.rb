class OrderEvent < ApplicationRecord
  belongs_to :order
  belongs_to :actor, polymorphic: true, optional: true

  validates :event_type, presence: true
end