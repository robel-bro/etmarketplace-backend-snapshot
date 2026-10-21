class Review < ApplicationRecord
  belongs_to :user
  belongs_to :product, optional: true
  belongs_to :vendor, optional: true
  belongs_to :reviewable, polymorphic: true, optional: true

  has_many_attached :images

  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :comment, presence: true
  validates :title, presence: true, if: :for_product?

  validates :user_id, uniqueness: { scope: :product_id, message: "You have already reviewed this product" }, if: :for_product?
  validates :user_id, uniqueness: { scope: :vendor_id, message: "You have already reviewed this shop" }, if: :for_vendor?
  validates :user_id, uniqueness: { scope: [:reviewable_type, :reviewable_id], message: "You have already reviewed this item" }, if: :for_reviewable?

  # ★ Update both product and vendor rating/review counts
  after_save :update_reviewable_rating
  after_destroy :update_reviewable_rating

  private

  def update_reviewable_rating
    if product.present?
      product.update_columns(
        rating: product.reviews.average(:rating).to_f.round(1),
        reviews_count: product.reviews.count
      )
    end

    if vendor.present?
      vendor.update_columns(
        rating: vendor.reviews.average(:rating).to_f.round(1),
        reviews_count: vendor.reviews.count
      )
    end
  end

  def for_product?
    product_id.present?
  end

  def for_vendor?
    vendor_id.present? && product_id.blank?
  end

  def for_reviewable?
    reviewable_type.present? && reviewable_id.present?
  end
end