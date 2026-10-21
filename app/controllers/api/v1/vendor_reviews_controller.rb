class Api::V1::VendorReviewsController < ApplicationController
  before_action :require_authentication

  # POST /api/v1/vendors/:vendor_id/reviews
  def create
    vendor = Vendor.approved.find(params[:vendor_id])
    rating = params[:rating] || params.dig(:review, :rating)
    comment = params[:comment] || params.dig(:review, :comment)

    review = vendor.reviews.new(
      rating: rating,
      comment: comment,
      user: current_user
    )

    if review.save
      render json: review_json(review), status: :created
    else
      # Log the errors so we can debug
      Rails.logger.debug "Review save failed: #{review.errors.full_messages}"
      render json: { errors: review.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/vendors/:vendor_id/reviews
  def index
    vendor = Vendor.find(params[:vendor_id])
    reviews = vendor.reviews.includes(:user).order(created_at: :desc)
    render json: reviews.map { |r| review_json(r) }
  end

  private

  def review_json(review)
    {
      id: review.id,
      rating: review.rating,
      comment: review.comment,
      user_name: review.user.email_address,
      created_at: review.created_at
    }
  end
end