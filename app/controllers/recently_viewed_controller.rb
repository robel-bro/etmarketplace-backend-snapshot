class RecentlyViewedController < ApplicationController
  allow_unauthenticated_access only: [:index, :create]

  def index
    # Guests see an empty list; logged-in users see their own
    if current_user
      recents = current_user.recently_vieweds
                            .order(viewed_at: :desc)
                            .limit(10)
                            .includes(:product)
      products = recents.map(&:product).compact
      render json: products.map { |p|
        { id: p.id, title: p.title, price: p.price, image_urls: p.image_urls }
      }
    else
      render json: []
    end
  end

  def create
    # Only persist for authenticated users
    if current_user
      product = Product.find(params[:product_id])
      recent = current_user.recently_vieweds.find_or_initialize_by(product: product)
      recent.update!(viewed_at: Time.current)
    end
    head :ok
  end
end