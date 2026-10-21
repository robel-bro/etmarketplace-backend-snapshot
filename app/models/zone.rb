class Zone < ApplicationRecord
  belongs_to :region
  has_many :woredas, dependent: :destroy
  has_many :addresses
  has_many :shipping_rates, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :region_id }
end