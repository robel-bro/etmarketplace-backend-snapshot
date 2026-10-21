class VendorsController < ApplicationController
  include Authentication
  before_action :require_authentication
  before_action :set_vendor, only: [:show, :update, :destroy]
  before_action :authorize_admin_or_owner, only: [:update, :destroy]
  before_action :authorize_admin, only: [:approve, :reject, :index_all]

  # GET /vendors (public) – approved vendors only (find-shop)
  def index
    vendors = Vendor.where(status: :approved).order(:business_name)
    render json: vendors.map { |v| vendor_public_json(v) }
  end

  # GET /vendors/all (admin only)
  def index_all
    vendors = Vendor.all.order(:business_name)
    render json: vendors.map { |v| vendor_admin_json(v) }
  end

  # GET /vendor (current seller) or /vendors/:id (public)
  def show
    if @vendor.status == 'approved' || current_user&.admin?
      render json: vendor_detail_json(@vendor)
    else
      head :not_found
    end
  end

  # POST /vendors – create a new vendor application
  def create
    if current_user.vendor.present?
      render json: { error: "User already has a vendor profile" }, status: :unprocessable_entity
      return
    end

    @vendor = current_user.build_vendor(vendor_params)
    @vendor.status = :pending

    if @vendor.save
      attach_documents(@vendor, params[:vendor])
      render json: vendor_detail_json(@vendor), status: :created
    else
      render json: { errors: @vendor.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /vendor or /vendors/:id
  def update
    if @vendor.update(vendor_params)
      attach_documents(@vendor, params[:vendor])
      render json: vendor_detail_json(@vendor)
    else
      render json: { errors: @vendor.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /vendors/:id – admin only
  def destroy
    @vendor.destroy
    head :no_content
  end

  # PATCH /vendors/:id/approve
  def approve
    vendor = Vendor.find(params[:id])
    if vendor.update(status: :approved, approved_at: Time.current)
      vendor.user.add_role("seller") unless vendor.user.seller?
      render json: { message: "Vendor approved", vendor: vendor_admin_json(vendor) }
    else
      render json: { errors: vendor.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /vendors/:id/reject
  def reject
    vendor = Vendor.find(params[:id])
    if vendor.update(status: :rejected, rejected_at: Time.current, rejection_reason: params[:reason])
      render json: { message: "Vendor rejected" }
    else
      render json: { errors: vendor.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /vendors/:id/products – public product list
  def products
    vendor = Vendor.find(params[:id])
    if vendor.status == 'approved' || current_user&.admin?
      products = vendor.products.where(status: :active)
      render json: products.map { |p| product_json(p) }
    else
      head :not_found
    end
  end

  private

  def set_vendor
    if params[:id].present?
      @vendor = Vendor.find(params[:id])
    elsif %w[show update].include?(action_name)
      # Singleton route /vendor
      @vendor = current_user.vendor || (head :not_found and return)
    else
      @vendor = Vendor.find(params[:id])
    end
  end

  def vendor_params
    params.require(:vendor).permit(
      :business_name, :tin, :national_id, :business_address,
      :commission_rate, :premium, :premium_expires_at,
      :description, :phone,
      :bank_name, :account_number, :account_name, :telebirr_number,
      :license_document, :id_document, :logo, :banner,
      :is_bulk_supplier   # ? NEW – bulk supplier checkbox
    )
  end

  def attach_documents(vendor, vendor_params)
    vendor.license_document.attach(vendor_params[:license_document]) if vendor_params[:license_document].present?
    vendor.id_document.attach(vendor_params[:id_document]) if vendor_params[:id_document].present?
    vendor.logo.attach(vendor_params[:logo]) if vendor_params[:logo].present?
    vendor.banner.attach(vendor_params[:banner]) if vendor_params[:banner].present?
  end

  def authorize_admin_or_owner
    return if current_user.admin? || @vendor.user == current_user
    head :forbidden
  end

  def authorize_admin
    head :forbidden unless current_user.admin?
  end

  # -- JSON serializers --

  def vendor_public_json(vendor)
    {
      id: vendor.id,
      business_name: vendor.business_name,
      logo_url: vendor.logo.attached? ? url_for(vendor.logo) : nil,
      banner_url: vendor.banner.attached? ? url_for(vendor.banner) : nil,
      rating: vendor.try(:rating) || 4.5,
      reviews_count: vendor.try(:reviews_count) || 0,
      business_address: vendor.try(:business_address)
    }
  end

  def vendor_admin_json(vendor)
    vendor_public_json(vendor).merge(
      status: vendor.status,
      tin: vendor.tin,
      national_id: vendor.national_id,
      user_id: vendor.user_id,
      user_email: vendor.user.email,
      approved_at: vendor.approved_at,
      rejected_at: vendor.rejected_at,
      rejection_reason: vendor.rejection_reason,
      commission_rate: vendor.commission_rate,
      premium: vendor.premium,
      premium_expires_at: vendor.premium_expires_at,
      license_document_url: vendor.license_document.attached? ? url_for(vendor.license_document) : nil,
      id_document_url: vendor.id_document.attached? ? url_for(vendor.id_document) : nil,
      is_bulk_supplier: vendor.is_bulk_supplier   # ? NEW
    )
  end

  def vendor_detail_json(vendor)
    vendor_public_json(vendor).merge(
      description: vendor.try(:description),
      phone: vendor.try(:phone),
      bank_name: vendor.try(:bank_name),
      account_number: vendor.try(:account_number),
      account_name: vendor.try(:account_name),
      telebirr_number: vendor.try(:telebirr_number),
      return_policy: vendor.try(:return_policy),
      shipping_policy: vendor.try(:shipping_policy),
      contact_phone: vendor.try(:contact_phone),
      social_links: vendor.try(:social_links) || {},
      is_open: vendor.is_open,
      accepting_orders: vendor.accepting_orders,
      reopen_at: vendor.reopen_at,
      is_bulk_supplier: vendor.is_bulk_supplier   # ? NEW
    )
  end

  def product_json(product)
    {
      id: product.id,
      title: product.title,
      price: product.price,
      original_price: product.original_price,
      image_urls: product.images.map { |img| url_for(img) },
      rating: product.rating,
      sold_count: product.sold_count,
      free_shipping: product.free_shipping
    }
  end
end