class StatsController < ApplicationController
  allow_unauthenticated_access only: [:index]

  def index
    stats = {
      products: Product.count,
      sellers: Vendor.approved.count,
      orders: Order.count,
      buyers: User.where(role_mask: 1).count  # adjust role logic if needed
    }
    render json: stats
  end
end