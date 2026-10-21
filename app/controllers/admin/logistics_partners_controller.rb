# app/controllers/admin/logistics_partners_controller.rb

class Admin::LogisticsPartnersController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin
  before_action :set_partner, only: [:show, :update, :destroy]

  # ─── List all partners ──────────────────────────
  def index
    @partners = LogisticsPartner.order(:name)
    if params[:dispatch_mode].present?
      @partners = @partners.where(dispatch_mode: params[:dispatch_mode])
    end

    # Preload counts and financials without N+1
    partner_ids = @partners.pluck(:id)
    vehicles_counts = Vehicle.where(logistics_partner_id: partner_ids).group(:logistics_partner_id).count
    drivers_counts = Driver.where(logistics_partner_id: partner_ids).group(:logistics_partner_id).count
    cod_balances = cod_balance_for_partners(partner_ids)
    total_earned = total_earned_for_partners(partner_ids)

    render json: @partners.map do |p|
      {
        id: p.id,
        name: p.name,
        phone: p.phone,
        email: p.user&.email,
        status: p.status,
        dispatch_mode: p.dispatch_mode,
        online: p.online,
        tin: p.tin,
        address: p.address,
        commission_rate: p.commission_rate,
        vehicles_count: vehicles_counts[p.id] || 0,
        drivers_count: drivers_counts[p.id] || 0,
        cod_balance: cod_balances[p.id] || 0.0,
        total_earned: total_earned[p.id] || 0.0
      }
    end
  end

  # ─── Show single partner (with extended data) ───
  def show
    render json: {
      id: @partner.id,
      name: @partner.name,
      phone: @partner.phone,
      email: @partner.user&.email,
      address: @partner.address,
      tin: @partner.tin,
      status: @partner.status,
      dispatch_mode: @partner.dispatch_mode,
      online: @partner.online,
      commission_rate: @partner.commission_rate,
      vehicles_count: @partner.vehicles.count,
      drivers_count: @partner.drivers.count,
      cod_balance: cod_balance_for_partner(@partner),
      total_earned: total_earned_for_partner(@partner),
      bank_name: @partner.respond_to?(:bank_name) ? @partner.bank_name : nil,
      account_number: @partner.respond_to?(:account_number) ? @partner.account_number : nil,
      account_name: @partner.respond_to?(:account_name) ? @partner.account_name : nil,
      telebirr_number: @partner.respond_to?(:telebirr_number) ? @partner.telebirr_number : nil,
      operating_region: @partner.respond_to?(:operating_region) ? @partner.operating_region : nil,
      business_license_url: @partner.business_license_doc.attached? ? rails_blob_url(@partner.business_license_doc) : nil,
      insurance_url: @partner.insurance_doc.attached? ? rails_blob_url(@partner.insurance_doc) : nil,
      tin_url: @partner.tin_doc.attached? ? rails_blob_url(@partner.tin_doc) : nil,
      logo_url: @partner.logo.attached? ? rails_blob_url(@partner.logo) : nil,
      vehicles: @partner.vehicles,
      drivers: @partner.drivers,
      rate_cards: @partner.rate_cards
    }
  end

  # ─── Create partner + user account ──────────────
  def create
    @partner = LogisticsPartner.new(partner_params)
    phone = normalize_phone(params[:phone])

    ActiveRecord::Base.transaction do
      if params[:password].present?
        user = User.new(
          phone: phone,
          email: params[:email],
          password: params[:password],
          full_name: params[:name]
        )
        unless user.save
          @partner.errors.add(:base, "User account: #{user.errors.full_messages.join(', ')}")
          raise ActiveRecord::Rollback
        end
        @partner.user = user
      end

      attach_files(@partner)
      @partner.save!

      if @partner.user.present?
        @partner.user.update!(logistics_partner_id: @partner.id)
      end

      log_admin_action('logistics_partner_created', @partner, { name: @partner.name })
      render json: @partner, status: :created
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::Rollback => e
    render json: { errors: @partner&.errors&.full_messages.presence || [e.message] }, status: :unprocessable_entity
  end

  # ─── Update partner ─────────────────────────────
  def update
    old_name = @partner.name
    phone = normalize_phone(params[:phone]) if params[:phone].present?

    @partner.assign_attributes(partner_params)
    @partner.phone = phone if phone.present?

    if @partner.save
      attach_files(@partner)
      if params[:email].present? && @partner.user.present?
        @partner.user.update(email: params[:email])
      end

      log_admin_action('logistics_partner_updated', @partner, { old_name: old_name, new_name: @partner.name })
      render json: @partner
    else
      render json: { errors: @partner.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # ─── Delete partner ─────────────────────────────
  def destroy
    info = { id: @partner.id, name: @partner.name }
    @partner.destroy
    log_admin_action('logistics_partner_deleted', nil, info)
    head :no_content
  rescue ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ─── COD reporting actions ──────────────────────
  def cod_balance
    cod_orders = Order.where(payment_method_enum: :cash_on_delivery,
                             payment_status: :completed,
                             status: :delivered)

    balances = cod_orders.joins(:delivery_requests)
                         .group('delivery_requests.logistics_partner_id')
                         .sum(:total)

    partners = LogisticsPartner.all.map do |partner|
      {
        id: partner.id,
        name: partner.name,
        owed_amount: balances.fetch(partner.id, 0).to_f
      }
    end

    unassigned_total = cod_orders.joins(:delivery_requests)
                                 .where(delivery_requests: { logistics_partner_id: nil })
                                 .sum(:total)
    if unassigned_total > 0
      partners << {
        id: nil,
        name: "Unassigned",
        owed_amount: unassigned_total.to_f
      }
    end

    render json: { partners: partners, total_owed: balances.values.sum.to_f + unassigned_total.to_f }
  end

  def cod_details
    start_date = params[:start_date] ? Date.parse(params[:start_date]) : 30.days.ago.to_date
    end_date   = params[:end_date]   ? Date.parse(params[:end_date])   : Date.today

    base_orders = Order.includes(:line_items, :delivery_requests, :user, :vendor, delivery_requests: :logistics_partner)
                       .where(payment_method_enum: :cash_on_delivery,
                              payment_status: :completed,
                              status: :delivered)
                       .where(delivered_at: start_date.beginning_of_day..end_date.end_of_day)
                       .order(delivered_at: :desc)

    if params[:partner_id].present?
      base_orders = base_orders.joins(:delivery_requests)
                               .where(delivery_requests: { logistics_partner_id: params[:partner_id] })
    end

    grouped = base_orders.group_by do |order|
      order.delivery_requests.where.not(logistics_partner_id: nil).first&.logistics_partner
    end

    result = grouped.map do |partner, orders|
      {
        partner: partner ? { id: partner.id, name: partner.name } : { id: nil, name: "Unassigned" },
        orders: orders.map { |order| detailed_order_json(order) }
      }
    end

    render json: { partners: result }
  rescue Date::Error
    render json: { error: 'Invalid date format. Use YYYY-MM-DD.' }, status: :unprocessable_entity
  end

  def reconcile_order
    order = Order.find(params[:order_id])
    unless order.payment_cash_on_delivery? && order.status == 'delivered'
      return render json: { error: 'Order is not a delivered COD order' }, status: :unprocessable_entity
    end

    order.update!(cod_reconciled: true)
    log_admin_action('cod_order_reconciled', order, { order_id: order.id })
    render json: { success: true, order_id: order.id, message: 'Order marked as reconciled.' }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Order not found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_partner
    @partner = LogisticsPartner.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Logistics partner not found' }, status: :not_found
    return false
  end

  def partner_params
    params.permit(
      :name, :phone, :tin, :address,
      :api_endpoint, :api_key, :active, :description,
      :base_rate, :per_km_rate, :min_charge,
      :delivery_speed, :estimated_days,
      :dispatch_mode, :remittance_required, :return_fee,
      :commission_rate, :status, :online,
      :bank_name, :account_number, :account_name,
      :telebirr_number, :operating_region,
      supported_vehicles: []
    ).tap do |whitelisted|
      %w[email password business_license insurance logo tin_doc].each do |f|
        whitelisted.delete(f) if whitelisted.key?(f)
      end
    end
  end

  # ★ UPDATED: Allow main admin or sub-admin with 'logistics' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions&.include?('logistics')
    head :forbidden
    false
  end

  def attach_files(partner)
    partner.business_license_doc.attach(params[:business_license]) if params[:business_license].present?
    partner.insurance_doc.attach(params[:insurance]) if params[:insurance].present?
    partner.logo.attach(params[:logo]) if params[:logo].present?
    partner.tin_doc.attach(params[:tin_doc]) if params[:tin_doc].present?
  end

  def normalize_phone(phone)
    return nil if phone.blank?
    phone = phone.to_s.strip
    phone = "+251#{phone[1..]}" if phone.start_with?('0')
    phone = "+#{phone}" if phone.match?(/\A\d{10}\z/)
    phone
  end

  def detailed_order_json(order)
    dr = order.delivery_requests.where.not(logistics_partner_id: nil).first
    partner_fee = dr&.estimated_cost.to_f
    total_collected = order.total.to_f
    net_owed = total_collected - partner_fee

    {
      id: order.id,
      delivered_at: order.delivered_at,
      buyer_name: order.user.full_name,
      buyer_phone: order.user.phone,
      shipping_address: order.shipping_address,
      products: order.line_items.map do |li|
        product = li.product
        {
          product_id: li.product_id,
          title: product&.title || 'N/A',
          quantity: li.quantity,
          unit_price: li.price.to_f,
          image_url: product&.first_image_url || ''
        }
      end,
      subtotal: order.line_items.sum { |li| li.price * li.quantity }.to_f,
      delivery_fee: order.shipping_cost.to_f,
      total_collected: total_collected,
      partner_fee: partner_fee,
      net_owed: net_owed,
      reconciled: order.respond_to?(:cod_reconciled?) ? order.cod_reconciled? : false
    }
  end

  def cod_balance_for_partner(partner)
    Order.joins(:delivery_requests)
         .where(payment_method_enum: :cash_on_delivery,
                payment_status: :completed,
                status: :delivered,
                delivery_requests: { logistics_partner_id: partner.id })
         .sum(:total).to_f
  end

  def cod_balance_for_partners(partner_ids)
    Order.joins(:delivery_requests)
         .where(payment_method_enum: :cash_on_delivery,
                payment_status: :completed,
                status: :delivered,
                delivery_requests: { logistics_partner_id: partner_ids })
         .group('delivery_requests.logistics_partner_id')
         .sum(:total)
  end

  def total_earned_for_partner(partner)
    PartnerPayout.where(logistics_partner: partner, status: :paid).sum(:amount).to_f
  end

  def total_earned_for_partners(partner_ids)
    PartnerPayout.where(logistics_partner_id: partner_ids, status: :paid)
                 .group(:logistics_partner_id)
                 .sum(:amount)
  end

  def log_admin_action(action, auditable, metadata = {})
    if defined?(AdminAuditLog) && AdminAuditLog.respond_to?(:log)
      AdminAuditLog.log(current_user, action, auditable, metadata)
    else
      Rails.logger.info "AdminAuditLog: #{action} by user #{current_user.id} metadata=#{metadata.inspect}"
    end
  end
end