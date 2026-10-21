class Admin::CollectionsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_collection, only: [:show, :update, :destroy, :refresh_products]

  def index
    @collections = Collection.all.order(display_order: :asc)
    render json: @collections.as_json(methods: :cover_image_url)
  end

  def show
    render json: @collection.as_json(methods: :cover_image_url)
  end

  def create
    @collection = Collection.new(collection_params.except(:cover_image))
    if @collection.save
      attach_cover_image if params[:collection][:cover_image].present?
      render json: @collection.as_json(methods: :cover_image_url), status: :created
    else
      render json: { errors: @collection.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @collection.update(collection_params.except(:cover_image))
      attach_cover_image if params[:collection][:cover_image].present?
      render json: @collection.as_json(methods: :cover_image_url)
    else
      render json: { errors: @collection.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @collection.destroy
    head :no_content
  end

  # New action to manually trigger product refresh
  def refresh_products
    @collection.refresh_products!
    render json: @collection.as_json(methods: :cover_image_url)
  end

  private

  def set_collection
    @collection = Collection.find(params[:id])
  end

  def collection_params
    raw = params.require(:collection).permit(:name, :slug, :description, :is_active, :start_date, :end_date, :display_order, :auto_criteria, :cover_image)
    if raw[:auto_criteria].is_a?(String)
      raw[:auto_criteria] = JSON.parse(raw[:auto_criteria]) rescue {}
    end
    raw
  end

  def attach_cover_image
    @collection.cover_image.attach(params[:collection][:cover_image])
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'collections' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('collections')
    head :forbidden
    false
  end
end