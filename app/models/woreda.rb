# app/models/woreda.rb
class Woreda < ApplicationRecord
  belongs_to :zone
  has_one :region, through: :zone
  has_many :addresses
  has_many :shipping_rates, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :zone_id }

  def self.find_by_coordinates(lat, lng)
    # 1. Try to find a woreda whose bounding box contains the point (raw SQL)
    box_sql = <<-SQL.squish
      SELECT id
      FROM woredas
      WHERE min_lat IS NOT NULL AND max_lat IS NOT NULL
        AND min_lat <= #{lat} AND max_lat >= #{lat}
        AND min_lng <= #{lng} AND max_lng >= #{lng}
      LIMIT 1
    SQL
    box_result = ActiveRecord::Base.connection.execute(box_sql).first
    if box_result
      return find_by(id: box_result['id'])
    end

    # 2. Fallback to nearest center point (Haversine)
    distance_sql = <<-SQL.squish
      SELECT id, (6371 * acos(cos(radians(#{lat})) * cos(radians(latitude)) * cos(radians(longitude) - radians(#{lng})) + sin(radians(#{lat})) * sin(radians(latitude)))) AS distance
      FROM woredas
      WHERE latitude IS NOT NULL AND longitude IS NOT NULL
      ORDER BY distance ASC
      LIMIT 1
    SQL
    result = ActiveRecord::Base.connection.execute(distance_sql).first
    return nil unless result
    find_by(id: result['id'])
  end
end