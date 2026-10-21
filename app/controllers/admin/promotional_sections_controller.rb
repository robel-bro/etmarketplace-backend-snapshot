class Admin::PromotionalSectionsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_section, only: [:show, :update, :destroy, :refresh_products]
  after_action :refresh_products_after_save, only: [:create, :update]
  after_action :notify_if_activated, only: [:create, :update]

  def index
    sections = PromotionalSection.all.order(display_order: :asc)
    render json: sections.as_json(include: :products)
  end

  def show
    render json: @section.as_json(include: :products)
  end

  def create
    @section = PromotionalSection.new(promotional_section_params)
    if @section.save
      render json: @section.as_json(include: :products), status: :created
    else
      render json: { errors: @section.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @section.system_generated?
      permitted = params.require(:promotional_section).permit(:display_order, :is_active, :max_products)
    else
      permitted = promotional_section_params
    end

    if @section.update(permitted)
      render json: @section.as_json(include: :products)
    else
      render json: { errors: @section.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    if @section.system_generated?
      render json: { error: "System sections cannot be deleted." }, status: :forbidden
    else
      @section.destroy
      head :no_content
    end
  end

  def refresh_products
    @section.refresh_products!
    render json: @section.as_json(include: :products)
  end

  private

  def set_section
    @section = PromotionalSection.find(params[:id])
  end

  def promotional_section_params
    params.require(:promotional_section).permit(
      :name, :slug, :section_type, :display_order, :is_active
    )
  end

  def refresh_products_after_save
    @section.refresh_products! unless @section.section_type.blank?
  end

  # ── New: Automatically send notifications to all buyers when a deal is activated ──
  def notify_if_activated
    return unless @section.is_active? && @section.products.any?

    @section.products.each do |product|
      User.where(role_mask: User::ROLES['buyer']).find_each do |user|
        NotificationService.notify(user, "flash_deal_started", {
          title: @section.name,
          discount: product.discount_percentage,
          product_id: product.id,
          product_name: product.title
        })
      end
    end
  end

  def authorize_admin
    head :forbidden unless current_user.admin?
  end
end