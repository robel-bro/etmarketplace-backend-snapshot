class RegionsController < ApplicationController
  # Allow anyone (even logged-out users) to see regions
  allow_unauthenticated_access only: [:index, :show]

  def index
    regions = Region.all.order(:name)
    render json: regions.as_json(only: [:id, :name])
  end

  def show
    region = Region.find(params[:id])
    render json: region.as_json(only: [:id, :name])
  end
end