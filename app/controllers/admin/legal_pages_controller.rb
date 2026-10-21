# app/controllers/admin/legal_pages_controller.rb
class Admin::LegalPagesController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_page, only: [:show, :update, :destroy]

  # GET /admin/legal_pages
  def index
    @pages = LegalPage.order(:key)
    render json: @pages
  end

  # GET /admin/legal_pages/:id
  def show
    render json: @page
  end

  # POST /admin/legal_pages
  def create
    page = LegalPage.new(page_params)
    if page.save
      render json: page, status: :created
    else
      render json: { errors: page.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /admin/legal_pages/:id
  def update
    if @page.update(page_params)
      render json: @page
    else
      render json: { errors: @page.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /admin/legal_pages/:id
  def destroy
    @page.destroy
    head :no_content
  end

  private

  def set_page
    @page = LegalPage.find(params[:id])
  end

  def page_params
    params.permit(:key, :title, :body, :published, :version)
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'legal_pages' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('legal_pages')
    head :forbidden
    false
  end
end