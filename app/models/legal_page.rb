# app/models/legal_page.rb
class LegalPage < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :title, :body, presence: true
  validates :version, numericality: { greater_than: 0 }

  scope :published, -> { where(published: true) }

  # Publish a page – bumps the version and records publish time
  def publish!
    update!(published: true, published_at: Time.current)
    increment!(:version) unless version_changed?
  end

  def unpublish!
    update!(published: false)
  end
end