# app/controllers/admin/vendors_controller.rb

class Admin::VendorsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  # GET /admin/vendors
  def index
    @vendors = Vendor.all
    render json: @vendors.map { |vendor| vendor_attributes(vendor) }
  end

  # GET /admin/vendors/:id
  def show
    @vendor = Vendor.find(params[:id])
    render json: vendor_attributes(@vendor)
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Vendor not found' }, status: :not_found
  end

  # PATCH /admin/vendors/:id/approve
  def approve
    @vendor = Vendor.find(params[:id])

    if @vendor.update(status: :approved, approved_at: Time.current)
      @vendor.user.add_role("seller")
      NotificationService.notify(@vendor.user, :vendor_approved)
      safe_audit('vendor_approved', @vendor, { business_name: @vendor.business_name })
      render json: { message: "Vendor approved and seller role granted", vendor: vendor_attributes(@vendor) }
    else
      render json: { errors: @vendor.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Vendor not found' }, status: :not_found
  end

  # PATCH /admin/vendors/:id/reject
  def reject
    @vendor = Vendor.find(params[:id])
    reason = params[:reason].presence || "No reason provided"
    if @vendor.update(status: :rejected, rejection_reason: reason)
      @vendor.user.remove_role("seller")
      NotificationService.notify(@vendor.user, :vendor_rejected, { reason: reason })
      safe_audit('vendor_rejected', @vendor, { business_name: @vendor.business_name, reason: reason })
      render json: { message: "Vendor rejected", vendor: vendor_attributes(@vendor) }
    else
      render json: { errors: @vendor.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Vendor not found' }, status: :not_found
  end

  # PATCH /admin/vendors/:id/suspend
  def suspend
    @vendor = Vendor.find(params[:id])
    if @vendor.update(status: :suspended)
      safe_audit('vendor_suspended', @vendor, { business_name: @vendor.business_name })
      render json: { message: "Vendor suspended", vendor: vendor_attributes(@vendor) }
    else
      render json: { errors: @vendor.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Vendor not found' }, status: :not_found
  end

  # PATCH /admin/vendors/:id/unsuspend
  def unsuspend
    @vendor = Vendor.find(params[:id])
    if @vendor.update(status: :approved)
      safe_audit('vendor_unsuspended', @vendor, { business_name: @vendor.business_name })
      render json: { message: "Vendor unsuspended", vendor: vendor_attributes(@vendor) }
    else
      render json: { errors: @vendor.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Vendor not found' }, status: :not_found
  end

  # POST /admin/vendors/:id/toggle_featured
  def toggle_featured
    @vendor = Vendor.find(params[:id])
    new_featured = !@vendor.featured
    featured_until = new_featured ? params[:featured_until].presence || 30.days.from_now : nil

    if @vendor.update(featured: new_featured, featured_until: featured_until)
      clear_homepage_cache
      safe_audit('vendor_featured_toggled', @vendor, { featured: new_featured })
      render json: vendor_attributes(@vendor)
    else
      render json: { errors: @vendor.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Vendor not found' }, status: :not_found
  end

  # POST /admin/vendors/:id/assign_membership
  def assign_membership
    @vendor = Vendor.find(params[:id])
    plan_id = params[:membership_plan_id].presence

    if plan_id
      begin
        plan = MembershipPlan.find(plan_id)
        @vendor.assign_membership_plan(plan)
        safe_audit('vendor_membership_assigned', @vendor, { plan: plan.name })
      rescue ActiveRecord::RecordNotFound
        return render json: { error: 'Membership plan not found' }, status: :not_found
      end
    else
      @vendor.remove_membership!
      safe_audit('vendor_membership_removed', @vendor, {})
    end

    clear_homepage_cache
    render json: vendor_attributes(@vendor)
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Vendor not found' }, status: :not_found
  end

  # DELETE /admin/vendors/:id
  def destroy
    @vendor = Vendor.find(params[:id])
    user = @vendor.user
    business_name = @vendor.business_name
    vendor_id = @vendor.id

    @vendor.destroy

    if user && user.vendor.nil?
      user.remove_role("seller") if user.seller?
      user.update!(refresh_token_digest: nil)
    end

    safe_audit('vendor_deleted', nil, { business_name: business_name, vendor_id: vendor_id })
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Vendor not found' }, status: :not_found
  rescue ActiveRecord::InvalidForeignKey
    render json: { error: 'Vendor cannot be deleted because they have associated records.' }, status: :unprocessable_entity
  end

  private

  def vendor_attributes(vendor)
    {
      id: vendor.id,
      business_name: vendor.business_name,
      tin: vendor.tin,
      business_address: vendor.business_address,
      national_id: vendor.national_id,
      telebirr_number: vendor.telebirr_number,
      is_bulk_supplier: vendor.is_bulk_supplier,
      status: vendor.status,
      rejection_reason: vendor.rejection_reason,
      approved_at: vendor.approved_at,
      rejected_at: vendor.rejected_at,
      commission_rate: vendor.commission_rate,
      premium: vendor.premium,
      premium_expires_at: vendor.premium_expires_at,
      featured: vendor.featured,
      featured_until: vendor.featured_until,
      membership_plan: vendor.membership_plan ? {
        id: vendor.membership_plan.id,
        name: vendor.membership_plan.name,
        badge_text: vendor.membership_plan.badge_text,
        expires_at: vendor.membership_expires_at
      } : nil,
      sponsored_products_count: vendor.products.where(sponsored: true).count,
      created_at: vendor.created_at,
      updated_at: vendor.updated_at,
      user_id: vendor.user_id,
      user: vendor.user ? {
        full_name: vendor.user.full_name,
        phone: vendor.user.phone
      } : nil,
      license_document_url: vendor.respond_to?(:license_document_url) ? vendor.license_document_url : nil,
      id_document_url: vendor.respond_to?(:id_document_url) ? vendor.id_document_url : nil,
      tin_certificate_url: vendor.respond_to?(:tin_certificate_url) ? vendor.tin_certificate_url : nil,
      business_license_url: vendor.respond_to?(:license_document_url) ? vendor.license_document_url : nil
    }
  end

  def clear_homepage_cache
    Rails.cache.delete_matched('homepage/*')
  rescue => e
    Rails.logger.warn "Failed to clear homepage cache: #{e.message}"
  end

  def safe_audit(action, record = nil, details = {})
    AdminAuditLog.log(current_user, action, record, details)
  rescue NameError => e
    Rails.logger.warn "AdminAuditLog not available: #{e.message}"
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'sellers' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('sellers')
    head :forbidden
    false
  end
end