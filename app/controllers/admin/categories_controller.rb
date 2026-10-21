class Admin::CategoriesController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_category, only: [:show, :update, :destroy]

  def index
    product_counts = Product.group(:category_id).count
    categories_tree = Category.arrange_as_array
    result = categories_tree.map { |node| category_json_with_count(node, product_counts) }
    render json: result
  end

  def show
    render json: category_json(@category)
  end

  def create
    @category = Category.new(create_params)
    if @category.save
      attach_image(@category) if params[:category] && params[:category][:image].present?
      AdminAuditLog.log(current_user, 'category_created', @category, { name: @category.name, parent_id: @category.parent_id })
      render json: category_json(@category), status: :created
    else
      render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    old_attrs = { name: @category.name, description: @category.description, commission_rate: @category.commission_rate }
    if @category.update(update_params)
      if params[:category] && params[:category][:image].present?
        @category.image.purge if @category.image.attached?
        @category.image.attach(params[:category][:image])
      end
      new_attrs = { name: @category.name, description: @category.description, commission_rate: @category.commission_rate }
      AdminAuditLog.log(current_user, 'category_updated', @category, { old: old_attrs, new: new_attrs })
      render json: category_json(@category)
    else
      render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    cat_info = { id: @category.id, name: @category.name }
    @category.destroy
    AdminAuditLog.log(current_user, 'category_deleted', nil, cat_info)
    head :no_content
  end

  private

  def set_category
    @category = Category.find(params[:id])
  end

  def create_params
    params.require(:category).permit(:name, :description, :parent_id, :commission_rate)
  end

  def update_params
    params.require(:category).permit(:name, :description, :commission_rate)
  end

  def attach_image(category)
    category.image.attach(params[:category][:image])
  end

  def category_json_with_count(node, product_counts)
    child_hashes = node.children.map { |child| category_json_with_count(child, product_counts) }
    direct_count = product_counts[node.id] || 0
    sub_count = child_hashes.sum { |ch| ch[:product_count] }
    total = direct_count + sub_count

    {
      id: node.id,
      name: node.name,
      description: node.description,
      commission_rate: node.commission_rate,
      parent_id: node.parent_id,
      image_url: node.image.attached? ? url_for(node.image) : nil,
      children: child_hashes,
      product_count: total
    }
  end

  def category_json(category)
    children = category.children.map { |c| category_json(c) }
    {
      id: category.id,
      name: category.name,
      description: category.description,
      commission_rate: category.commission_rate,
      parent_id: category.parent_id,
      image_url: category.image.attached? ? url_for(category.image) : nil,
      children: children,
      product_count: (category.respond_to?(:products) ? category.products.size : 0) +
                     children.sum { |c| c[:product_count] || 0 }
    }
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'categories' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('categories')
    head :forbidden
    false
  end
end