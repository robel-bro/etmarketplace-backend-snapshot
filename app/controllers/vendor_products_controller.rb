class VendorProductsController < ApplicationController
  before_action :require_authentication
  before_action :ensure_vendor

  def index
    products = current_user.vendor.products
    render json: products.as_json(only: [:id, :title, :description, :price, :stock, :status], methods: [:image_urls])
  end

  private

  def ensure_vendor
    head :forbidden unless current_user.vendor.present?
  end
end