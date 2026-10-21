class Region < ApplicationRecord
  has_many :zones, dependent: :destroy
  has_many :woredas, through: :zones
  has_many :addresses
  has_many :shipping_rates, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end