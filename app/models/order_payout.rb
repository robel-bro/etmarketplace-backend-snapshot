class OrderPayout < ApplicationRecord
  belongs_to :order
  belongs_to :payout
end