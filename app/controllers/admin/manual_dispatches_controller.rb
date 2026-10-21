# app/controllers/admin/manual_dispatches_controller.rb
class Admin::ManualDispatchesController < ApplicationController
  before_action :require_authentication
  before_action :ensure_admin

  # GET /admin/manual_dispatches
  def index
    dispatches = ManualDispatch.includes(:delivery_request, :logistics_partner, :admin_user)
                               .order(created_at: :desc)
    render json: dispatches.map { |md| manual_dispatch_json(md) }
  end

  # GET /admin/manual_dispatches/:id
  def show
    md = ManualDispatch.find(params[:id])
    render json: manual_dispatch_json(md, include_details: true)
  end

  # PATCH /admin/manual_dispatches/:id/assign
  def assign
    md = ManualDispatch.find(params[:id])
    partner = LogisticsPartner.active.find_by(id: params[:logistics_partner_id])
    return render json: { error: "Invalid partner" }, status: :unprocessable_entity unless partner

    md.update!(
      logistics_partner: partner,
      admin_user: current_user,
      status: :contacted
    )
    render json: manual_dispatch_json(md)
  end

  # PATCH /admin/manual_dispatches/:id/update_status
  def update_status
    md = ManualDispatch.find(params[:id])
    new_status = params[:status]
    unless ManualDispatch.statuses.keys.include?(new_status)
      return render json: { error: "Invalid status" }, status: :unprocessable_entity
    end

    md.update!(status: new_status, admin_user: current_user)

    if new_status == 'delivered'
      dr = md.delivery_request
      dr.update!(status: 'delivered', delivered_at: Time.current)

      # Update the CheckoutGroup if all orders in the group are delivered
      group = CheckoutGroup.find_by(id: dr.order.checkout_group_id)
      if group
        group.orders.reload
        if group.orders.all? { |o| o.status == 'delivered' }
          group.update!(status: :delivered)
        end
      end
    end

    render json: manual_dispatch_json(md)
  end

  # POST /admin/manual_dispatches/:id/notes
  def notes
    md = ManualDispatch.find(params[:id])
    note = params[:note]
    md.update!(notes: (md.notes.present? ? "#{md.notes}\n#{note}" : note))
    render json: { success: true, notes: md.notes }
  end

  # POST /admin/manual_dispatches/:id/evidence
  def evidence
    md = ManualDispatch.find(params[:id])
    evidence_item = {
      type: 'photo',
      url: params[:url] || params[:file],
      uploaded_at: Time.current.iso8601
    }
    dr = md.delivery_request
    evidence_list = (dr.evidence || []) << evidence_item
    dr.update!(evidence: evidence_list)
    render json: { success: true, evidence: evidence_list }
  end

  private

  # ★ UPDATED: Allow main admin or sub-admin with 'manual_dispatches' permission
  def ensure_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions&.include?('manual_dispatches')
    head :forbidden
    false
  end

  def manual_dispatch_json(md, include_details: false)
    dr = md.delivery_request
    group = CheckoutGroup.find_by(id: dr.order.checkout_group_id) if dr.order
    base = {
      id: md.id,
      delivery_request_id: md.delivery_request_id,
      status: md.status,
      notes: md.notes,
      admin_user: md.admin_user ? { id: md.admin_user.id, name: md.admin_user.full_name } : nil,
      logistics_partner: md.logistics_partner ? { id: md.logistics_partner.id, name: md.logistics_partner.name } : nil,
      created_at: md.created_at,
      updated_at: md.updated_at,
      buyer_name: dr.order.user.full_name,
      buyer_address: dr.delivery_address,
      buyer_phone: dr.delivery_contact_phone,
      delivery_pin: dr.order.delivery_pin,
      pickup_points: dr.pickup_points,
      consolidated_shipping: group&.buyer_shipping_cost
    }
    if include_details
      base[:manifest] = group&.manifest
    end
    base
  end
end