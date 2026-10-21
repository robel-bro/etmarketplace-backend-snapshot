class Admin::ZonesController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_zone, only: [:show, :update, :destroy]

  def index
    @zones = Zone.all
    render json: @zones.as_json(include: :region)
  end

  def show
    render json: @zone.as_json(include: [:region, :woredas])
  end

  def create
    @zone = Zone.new(zone_params)
    if @zone.save
      render json: @zone, status: :created
    else
      render json: { errors: @zone.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @zone.update(zone_params)
      render json: @zone
    else
      render json: { errors: @zone.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @zone.destroy
    head :no_content
  end

  private

  def set_zone
    @zone = Zone.find(params[:id])
  end

  def zone_params
    params.require(:zone).permit(:name, :region_id)
  end

  def authorize_admin
    head :forbidden unless current_user.admin?
  end
end