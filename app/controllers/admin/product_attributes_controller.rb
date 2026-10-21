class Admin::ProductAttributesController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_attribute, only: [:edit, :update, :destroy]

  def index
    @attributes = ProductAttribute.all
  end

  def new
    @attribute = ProductAttribute.new
  end

  def create
    @attribute = ProductAttribute.new(attribute_params)
    if @attribute.save
      redirect_to admin_product_attributes_path, notice: 'Attribute created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @attribute.update(attribute_params)
      redirect_to admin_product_attributes_path, notice: 'Attribute updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @attribute.destroy
    redirect_to admin_product_attributes_path, notice: 'Attribute deleted.'
  end

  private

  def set_attribute
    @attribute = ProductAttribute.find(params[:id])
  end

  def attribute_params
    params.require(:product_attribute).permit(:name, :category_id)
  end

  # ★ This controller remains main admin only – no sub-admin permission
  def authorize_admin
    head :forbidden unless current_user.admin?
  end
end