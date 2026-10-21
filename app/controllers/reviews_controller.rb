class ReviewsController < ApplicationController
  before_action :require_authentication, except: [:index]
  before_action :set_review, only: [:update, :destroy]
  before_action :ensure_purchased, only: [:create]   # ★ new

  # GET /products/:product_id/reviews
  # GET /vendors/:vendor_id/reviews
  # GET /packages/:package_id/reviews
  def index
    if params[:product_id]
      @reviews = Review.where(product_id: params[:product_id]).includes(:user)
    elsif params[:vendor_id]
      @reviews = Review.where(vendor_id: params[:vendor_id]).includes(:user)
    elsif params[:package_id]
      @reviews = Review.where(reviewable_type: 'Package', reviewable_id: params[:package_id]).includes(:user)
    elsif params[:reviewable_type] && params[:reviewable_id]
      @reviews = Review.where(reviewable_type: params[:reviewable_type],
                              reviewable_id: params[:reviewable_id]).includes(:user)
    else
      @reviews = Review.none
    end
    render json: @reviews.as_json(include: { user: { only: [:id, :name] } })
  end

  def create
    @review = current_user.reviews.new(review_params)
    if @review.save
      render json: @review, status: :created
    else
      render json: { errors: @review.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @review.update(review_params)
      render json: @review
    else
      render json: { errors: @review.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @review.destroy
    head :no_content
  end

  private

  def set_review
    @review = Review.find(params[:id])
    unless current_user.admin? || @review.user == current_user
      head :forbidden
    end
  end

  # ★ New: Only allow reviews from verified purchasers
  def ensure_purchased
    product_id = review_params[:product_id]
    package_id = review_params[:reviewable_id] if review_params[:reviewable_type] == 'Package'

    if product_id.present?
      purchased = current_user.orders.joins(:line_items)
                             .where(orders: { status: [:delivered, :completed] })
                             .where(line_items: { product_id: product_id })
                             .exists?
      unless purchased
        render json: { error: "You must purchase this product before reviewing." }, status: :unprocessable_entity
        return
      end
    elsif package_id.present?
      purchased = current_user.orders.joins(:line_items)
                             .where(orders: { status: [:delivered, :completed] })
                             .where(line_items: { package_id: package_id })
                             .exists?
      unless purchased
        render json: { error: "You must purchase this package before reviewing." }, status: :unprocessable_entity
        return
      end
    end
  end

  def review_params
    params.require(:review).permit(:product_id, :vendor_id,
                                   :reviewable_type, :reviewable_id,
                                   :rating, :title, :comment, images: [])
  end
end