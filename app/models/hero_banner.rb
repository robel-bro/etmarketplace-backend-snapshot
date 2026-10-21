class HeroBanner < ApplicationRecord
  has_one_attached :image

  validates :title, :start_date, :end_date, presence: true
  validates :display_order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> {
    where(is_active: true)
      .where('start_date <= ?', Time.current)
      .where('end_date >= ?', Time.current)
      .order(:display_order)
  }

  def image_url
    Rails.application.routes.url_helpers.rails_blob_url(image) if image.attached?
  rescue StandardError
    nil
  end
end