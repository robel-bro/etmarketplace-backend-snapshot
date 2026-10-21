class ReportsController < ApplicationController
  before_action :require_authentication, only: [:create]
  before_action :set_product, only: [:create]

  def create
    @report = current_user.reports.build(report_params)
    @report.product = @product

    if @report.save
      # Notify admin (optional)
      AdminMailer.new_report(@report).deliver_later if defined?(AdminMailer)
      render json: @report, status: :created
    else
      render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_product
    @product = Product.find(params[:product_id])
  end

  def report_params
    params.require(:report).permit(:reason, :comment)
  end
end