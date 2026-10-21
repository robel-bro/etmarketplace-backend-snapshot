# app/controllers/admin/financial_ledgers_controller.rb

class Admin::FinancialLedgersController < ApplicationController
  before_action :require_authentication
  before_action :authorize_admin

  # GET /admin/financial_ledgers
  def index
    begin
      start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : 30.days.ago.to_date
      end_date   = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today
    rescue Date::Error
      return render json: { error: 'Invalid date format. Use YYYY-MM-DD.' }, status: :unprocessable_entity
    end

    @ledgers = FinancialLedger.between(start_date, end_date).recent

    # Correct totals: total_in = money entering platform (debit cash), total_out = money leaving (credit cash)
    total_in  = @ledgers.where(debit_account: FinancialLedgerService::ACCOUNTS[:cash_bank]).sum(:amount)
    total_out = @ledgers.where(credit_account: FinancialLedgerService::ACCOUNTS[:cash_bank]).sum(:amount)
    net       = total_in - total_out

    render json: {
      entries: @ledgers.as_json,
      totals: {
        total_in: total_in.to_f,
        total_out: total_out.to_f,
        net: net.to_f,
        count: @ledgers.count
      }
    }
  end

  private

  # ★ UPDATED: Allow main admin or sub-admin with 'financial_ledger' permission
  def authorize_admin
    return true if current_user&.admin?
    return true if current_user&.sub_admin? && current_user.permissions.include?('financial_ledger')
    head :forbidden
    false
  end
end