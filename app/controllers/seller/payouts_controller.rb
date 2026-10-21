# app/controllers/seller/payouts_controller.rb
class Seller::PayoutsController < Seller::BaseController
  def index
    vendor = current_user.vendor
    service = PayoutService.new(vendor)
    summary = service.summary

    # Calculate tax breakdown from completed orders that are not yet paid out
    eligible_orders = vendor.orders
                            .where(payment_status: :completed, status: :completed)
                            .where.not(id: OrderPayout.select(:order_id))

    total_commission = eligible_orders.sum(:commission_amount).to_f
    # VAT is 15% of commission if platform is VAT‑registered (we'll read from settings)
    vat_rate = (Setting.get('tax_and_fees', {})['vat_rate'] || 0).to_f / 100.0
    vat_total = (total_commission * vat_rate).round(2)

    # WHT is not yet deducted automatically, but we can show the potential amount
    wht_rate = (Setting.get('tax_and_fees', {})['withholding_tax_rate'] || 0).to_f / 100.0
    wht_total = (summary[:total_earned] * wht_rate).round(2)

    render json: {
      summary: {
        total_earned: summary[:total_earned].to_f,
        pending: summary[:pending].to_f,
        available: summary[:available].to_f,
        commission_total: total_commission,
        vat_total: vat_total,
        wht_total: wht_total
      },
      payouts: vendor.payouts.order(created_at: :desc).map { |p| payout_json(p) }
    }
  end

  def create
    vendor = current_user.vendor
    service = PayoutService.new(vendor)

    begin
      payout = service.request_payout(
        period_start: params[:period_start],
        period_end: params[:period_end]
      )
      render json: payout_json(payout), status: :created
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def payout_json(payout)
    {
      id: payout.id,
      date: payout.created_at.strftime("%Y-%m-%d"),
      amount: payout.amount.to_f,
      status: payout.status
    }
  end
end