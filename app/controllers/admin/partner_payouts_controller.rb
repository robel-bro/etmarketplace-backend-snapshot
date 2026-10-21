# app/controllers/admin/partner_payouts_controller.rb

class Admin::PartnerPayoutsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  # GET /admin/partner_payouts
  def index
    begin
      start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : 30.days.ago.to_date
      end_date   = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today
    rescue Date::Error
      return render json: { error: 'Invalid date format. Use YYYY-MM-DD.' }, status: :unprocessable_entity
    end

    payouts = PartnerPayout.includes(:logistics_partner)
                           .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
                           .order(created_at: :desc)

    # Count distinct partners safely (no ORDER BY conflict)
    partner_ids = PartnerPayout.where(created_at: start_date.beginning_of_day..end_date.end_of_day)
                               .distinct.pluck(:logistics_partner_id).compact.uniq

    totals = {
      total_paid: payouts.where(status: :paid).sum(:amount).to_f,
      count: payouts.count,
      partners: partner_ids.size
    }

    render json: {
      payouts: payouts.as_json(include: :logistics_partner),
      totals: totals
    }
  end

  # GET /admin/partner_payouts/:id
  def show
    payout = PartnerPayout.includes(:logistics_partner).find(params[:id])
    render json: payout.as_json(include: :logistics_partner)
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Payout not found' }, status: :not_found
  end

  private

  # ★ UPDATED: Allow main admin, or sub-admin with either 'payouts' or 'partner_payouts' permission
  def authorize_admin
    return true if current_user&.admin?

    if current_user&.sub_admin?
      return true if current_user.permissions.include?('payouts')
      return true if current_user.permissions.include?('partner_payouts')
    end

    head :forbidden
    false
  end
end