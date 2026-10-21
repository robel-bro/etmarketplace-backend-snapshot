class Admin::RegionsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  def index
    @regions = Region.all
    render json: @regions
  end

  def show
    @region = Region.find(params[:id])
    render json: @region.as_json(include: { zones: { include: :woredas } })
  end

  def create
    @region = Region.new(region_params)
    if @region.save
      render json: @region, status: :created
    else
      render json: { errors: @region.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    @region = Region.find(params[:id])
    if @region.update(region_params)
      render json: @region
    else
      render json: { errors: @region.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @region = Region.find(params[:id])
    @region.destroy
    head :no_content
  end

  private

  def region_params
    params.require(:region).permit(:name)
  end

  def authorize_admin
    head :forbidden unless current_user.admin?
  end
end