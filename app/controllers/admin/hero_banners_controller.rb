class Admin::HeroBannersController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_hero_banner, only: [:update, :destroy]

  def index
    @hero_banners = HeroBanner.order(:display_order)
    render json: @hero_banners.as_json(methods: :image_url)
  end

  def create
    @hero_banner = HeroBanner.new(hero_banner_params.except(:image))
    if @hero_banner.save
      if params[:hero_banner][:image].present?
        @hero_banner.image.attach(params[:hero_banner][:image])
      end
      AdminAuditLog.log(current_user, 'hero_banner_created', @hero_banner, { title: @hero_banner.title })
      render json: @hero_banner.as_json(methods: :image_url), status: :created
    else
      render json: { errors: @hero_banner.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    old_title = @hero_banner.title
    if @hero_banner.update(hero_banner_params.except(:image))
      if params[:hero_banner][:image].present?
        @hero_banner.image.purge if @hero_banner.image.attached?
        @hero_banner.image.attach(params[:hero_banner][:image])
      end
      AdminAuditLog.log(current_user, 'hero_banner_updated', @hero_banner, { old_title: old_title, new_title: @hero_banner.title })
      render json: @hero_banner.as_json(methods: :image_url), status: :ok
    else
      render json: { errors: @hero_banner.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    info = { id: @hero_banner.id, title: @hero_banner.title }
    @hero_banner.destroy
    AdminAuditLog.log(current_user, 'hero_banner_deleted', nil, info)
    head :no_content
  end

  def reorder
    old_order = HeroBanner.order(:display_order).pluck(:id, :display_order).to_h
    params[:order].each_with_index do |id, index|
      HeroBanner.find(id).update(display_order: index + 1)
    end
    AdminAuditLog.log(current_user, 'hero_banner_reordered', nil, { old_order: old_order, new_order: params[:order] })
    head :ok
  end

  private

  def set_hero_banner
    @hero_banner = HeroBanner.find(params[:id])
  end

  def hero_banner_params
    params.require(:hero_banner).permit(:title, :subtitle, :link, :start_date, :end_date, :display_order, :is_active, :image)
  end

  # ★ This controller remains main admin only – no sub-admin permission
  def authorize_admin
    head :forbidden unless current_user&.admin?
  end
end