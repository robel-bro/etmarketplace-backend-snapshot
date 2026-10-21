class Admin::WoredasController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_woreda, only: [:show, :update, :destroy]

  def index
    @woredas = Woreda.all
    render json: @woredas.as_json(include: { zone: { include: :region } })
  end

  def show
    render json: @woreda.as_json(include: { zone: { include: :region } })
  end

  def create
    @woreda = Woreda.new(woreda_params)
    if @woreda.save
      render json: @woreda, status: :created
    else
      render json: { errors: @woreda.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @woreda.update(woreda_params)
      render json: @woreda
    else
      render json: { errors: @woreda.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @woreda.destroy
    head :no_content
  end

  private

  def set_woreda
    @woreda = Woreda.find(params[:id])
  end

  def woreda_params
    params.require(:woreda).permit(:name, :zone_id)
  end

  def authorize_admin
    head :forbidden unless current_user.admin?
  end
end