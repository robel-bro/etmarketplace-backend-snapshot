# app/models/address_cache.rb
class AddressCache < ApplicationRecord
  validates :raw_address, presence: true, uniqueness: true
end