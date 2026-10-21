class Category < ApplicationRecord
  has_ancestry
  has_one_attached :image   # ← ★ NEW – Active Storage for category images

  # Package associations
  has_many :package_categories, dependent: :destroy
  has_many :packages, through: :package_categories

  # Attribute catalog associations
  has_many :category_attributes, dependent: :destroy
  has_many :defined_attributes, through: :category_attributes, source: :attr  # ← fixed

  # Validations
  validates :name, presence: true
  validates :name, uniqueness: { scope: :ancestry }, if: :name_changed?

  def self.arrange_as_array(options = {}, hash = nil)
    hash ||= arrange(options)
    arr = []
    hash.each do |node, children|
      arr << node
      arr += arrange_as_array(options, children) unless children.empty?
    end
    arr
  end

  def effective_commission_rate
    if commission_rate.present?
      commission_rate
    elsif parent
      parent.effective_commission_rate
    else
      nil
    end
  end

  # Returns the URL for the attached image
  def image_url
    return nil unless image.attached?
    Rails.application.routes.url_helpers.rails_blob_url(image, only_path: false)
  end
end