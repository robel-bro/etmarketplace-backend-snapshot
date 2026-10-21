# app/models/driver.rb
class Driver < ApplicationRecord
  belongs_to :logistics_partner
  belongs_to :vehicle, optional: true

  has_one_attached :photo
  has_one_attached :license_photo

  enum :status, { available: 0, on_delivery: 1, inactive: 2 }

  validates :name, :phone, presence: true
  validates :license_number, presence: true, allow_blank: true

  scope :available, -> { where(status: :available) }

  # Helper to generate full photo URL
  def photo_url
    if photo.attached?
      Rails.application.routes.url_helpers.rails_blob_url(photo, only_path: false)
    else
      nil
    end
  end

  def license_photo_url
    if license_photo.attached?
      Rails.application.routes.url_helpers.rails_blob_url(license_photo, only_path: false)
    else
      nil
    end
  end

  def available?
    status == 'available'
  end

  def on_delivery?
    status == 'on_delivery'
  end

  def mark_available!
    update!(status: :available)
  end

  def mark_on_delivery!
    update!(status: :on_delivery)
  end
end