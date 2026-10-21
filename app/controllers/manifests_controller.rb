class ManifestsController < ApplicationController
  # No authentication required if shared as a link – secure with token if needed.
  def show
    dr = DeliveryRequest.find(params[:id])
    group = CheckoutGroup.find_by(id: dr.order.checkout_group_id)
    @manifest = group&.manifest || []
    render :show
  end
end