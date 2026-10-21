class Admin::ReportsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  def index
    @reports = Report.includes(:user, :product).order(created_at: :desc)
    render json: @reports.as_json(include: {
      user: { only: [:full_name, :phone] },
      product: { only: [:title] }
    })
  end

  def update
    report = Report.find(params[:id])
    if report.update(status: params[:status])
      render json: report
    else
      render json: { errors: report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  # ★ UPDATED: Allow main admin or sub-admin with 'reports' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('reports')
    head :forbidden
    false
  end
end