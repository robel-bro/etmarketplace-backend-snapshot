# app/controllers/seller/base_controller.rb

class Seller::BaseController < ApplicationController
  before_action :require_seller!
  before_action :ensure_vendor
  before_action :ensure_vendor_active!

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def ensure_vendor
    head :forbidden unless current_user.vendor.present?
  end

  def ensure_vendor_active!
    if current_user.vendor&.suspended?
      render json: { error: "Your seller account is currently suspended." }, status: :forbidden
    end
  end

  def user_not_authorized
    render json: { error: "You are not authorized to perform this action." }, status: :forbidden
  end
end